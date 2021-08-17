#!/bin/perl

use strict;

use Getopt::Long;
use File::Temp qw/ tempfile tempdir /;
use File::Basename;
use File::Spec::Functions 'catfile';
use POSIX;

my $dirname = dirname(__FILE__);

my $rom_title;
my $rom_ver;
my $rom_ver_str;
my $rom_copy;
my $rom_output;
my $noasm;
my $calcoffs;

my $DATA_OFFSET = 0x805D;

GetOptions(
	"title=s" => \$rom_title,
	"version=i" => \$rom_ver,
	"copy=s" => \$rom_copy,
	"output=s" => \$rom_output,
	"noasm" => \$noasm,
	"calcoffs" => \$calcoffs
	) or usage("Bad command line parameters");

if (!$calcoffs) {
	$rom_title or usage("Missing title");
	defined($rom_ver) or usage("Missing version number");
	$rom_ver >= 0 && $rom_ver <= 255 or usage("Copy right should be a number 0..255");
	$rom_copy or usage("Missing copyright message");
	$rom_copy =~ /^\(C\)/ or die "Copyright message must start \"(C)\"";
	$rom_output or usage("Missing output filename");
	$rom_ver_str = $rom_ver;
} else {
	$rom_title = "";
	$rom_ver_str = "";
	$rom_ver = 0;
	$rom_copy = "";
}

sub usage($) {
	my ($msg) = @_;

	if ($msg) {
		print STDERR $msg;
	}

	print STDERR "

mkromfs.pl --title=<rom title> --version=<rom version> --copy=<copyright> --output=<output> --noasm [file...]


If --noasm is specified then the output is the source code for beebasm rather than the output
If --calcoffs is specified then the script will recalculate the DATA_OFFSET parameter and print it on screen in hex.
";

	die;
}

##CRC function sanity check against NAUG example
##printf "%02X\n", crc(pack("Z* L L S S C L", "*EXAMPLE*", 0, 0, 0, 0, 0xC0, 0x809E));

$DATA_OFFSET += length($rom_ver_str) + length($rom_title) + length($rom_copy);

my $data;

if (!$calcoffs) {

	my %already = ();

	rfs_mkfile("*$rom_title*", 0, 0, 0, []);

	$#ARGV < 0 && "No files specified...exiting";

	for my $fin (@ARGV) {
		print "PROCESSING FILE: $fin...";
		if ( ! -e $fin ) {
			print "doesn't exist!\n";
			die "File $fin doesn't exist";
		}

		my $filebase = $fin;
		my $fileinfo = $filebase . ".inf";
		if ($filebase =~ /^(.*?)\.inf$/i) {
			$fileinfo = $filebase;
			$filebase = $1;
		}

		if ($already{$filebase}) {
			print "skipping - already done\n";
			next;
		}

		

		my $inf_info = {
			name => $filebase,
			exec => 0,
			load => 0,
			access => 0
		};


		if (-e $fileinfo) {
			open (my $fh_inf, "<", $fileinfo) or die "Error opening .inf file $fileinfo : $!";
			my $l = <$fh_inf>;
			decodeinf($l, $inf_info);
			close $fh_inf;
		}

		$inf_info->{name} =~ s/^\$\.//;

		open (my $fh_bin, "<:raw", $filebase) or die "Error opening input file $filebase : $!";
		my $binc = do { local $/; <$fh_bin> };
		close $fh_bin;
		my @bin = unpack("C*", $binc);
		rfs_mkfile($inf_info->{name}, $inf_info->{load}, $inf_info->{exec}, $inf_info->{exec} & 0x08, \@bin) or die "Error adding file $filebase : $!";

		print "done\n";

		$already{$filebase}=$fin;
	}
}


$data .= "
		EQUB	&2B		\\END OF ROM MARKER
		";

my $fn_asmt = catfile($dirname, "handlesvc.asm");

open(my $fh_asmt, "<", $fn_asmt) or die "Cannot open $fn_asmt for input $!";

my $fh_asm;
my $fn_asm;

if ($noasm && !$calcoffs) {
	$fn_asm = $rom_output;
	open ($fh_asm, ">", $fn_asm) or die "Cannot open $fn_asm $!";
} else {
	($fh_asm, $fn_asm) = tempfile(UNLINK => 1);
}


while (<$fh_asmt>) {
	s/\{version\}/$rom_ver/g;
	s/\{copyright\}/\"$rom_copy\"/g;
	s/\{version_str\}/\"$rom_ver_str\"/g;
	s/\{rom_title\}/\"$rom_title\"/g;
	s/\{data\}/$data/g;

	print $fh_asm $_;
}

if ($calcoffs) {
	my ($fh_tmp, $fn_tmp) = tempfile(UNLINK => 1);
	close($fh_tmp);
	system("beebasm", "-i", $fn_asm, "-o", $fn_tmp) and die "Error running beebasm $!";	
	printf "DATA_OFFSET: %04X\n", 0x8000 + -s $fn_tmp;	
} elsif ($noasm) {
	print "Source code for rom written to $fn_asm\n";
} else {
	system("beebasm", "-i", $fn_asm, "-o", $rom_output) and die "Error running beebasm $!";
	print "Rom written to $rom_output\n";
}


sub decodeinf($$) {
	my ($inf, $out) = @_;

	if ($inf =~ /
		([^\s]+)
		(\s+ ([0-9A-F]{6,8}) 
			(\s+ ([0-9A-F]{6,8}) 
				(\s+ ([0-9A-F]{6,8}) 
					(\s+ ([0-9A-F]{2}|L) 
					)? 
				)? 
			)? 
		)?		/x) {
		
		$out->{name} = $1;
		if ($3) {
			$out->{load} = hex($3);
		}
		if ($5) {
			$out->{exec} = hex($5);
		}
		if ($9 eq "L") {
			$out->{access} = 8;
		}
		elsif ($9) {
			$out->{access} = hex($9);
		}

		$out->{adfsname} =~ s/^\$\.//;
	}
}

sub rfs_mkfile($$$$$) {
	my ($name, $load, $exec, $lock, $datr) = @_;

	my $name_munged = uc($name);
	$name_munged =~ s/.*?(\\|\/)//g;
	$name_munged =~ s/\s/_/g;
	$name_munged =~ s/[_]+/_/g;
	$name_munged = substr($name_munged, 0, 10);
	my @dat = @{$datr};

	my $headersize = 1 + length($name_munged) + 1 + 4 + 4 + 2 + 2 + 1 + 4 + 2;
	my $datablocksize = 0;

	my $numdatablocks = ceil((scalar @dat) / 256);
print "===$numdatablocks\n";

	my $totalsize = $headersize;
	if ($numdatablocks > 0) {
		if ($numdatablocks > 1) {
			$totalsize += $headersize; # end header
			if ($numdatablocks > 2) {
				$totalsize += $numdatablocks-2; # inter block gaps = 1 char
			}
		}
		$totalsize += $numdatablocks*2; # crcs
		$totalsize += scalar @dat; # the data
	}

	$DATA_OFFSET += $totalsize;

	my $blockno = 0;
	while ($blockno == 0 or scalar(@dat)) {

		my @thisdat = splice(@dat, 0, 256);

		my $datlen = scalar @thisdat;
		if ($datlen != 0)
		{
			$datablocksize = $datlen + 2;
		}


		my $flag = ((scalar @dat==0)?0x80:0x00) + (($lock)?0x01:0x00) + (($datlen == 0)?0x40:0x00);
	
		if ($blockno == 0 or $flag & 0x80) {
			#first or last block - emit a header

			my $bin = pack("Z* L L S S C L", $name_munged, $load, $exec, $blockno, $datlen, $flag, $DATA_OFFSET);
			my $hdrcrc = crc($bin);


		#	print "====";
		#	for (my $i = 0; $i < length($bin); $i++) {
		#
		#		if (($i % 8) == 0) {
		#			print "\n";
		#		}
		#		printf " %02X", ord(substr($bin, $i, 1));
		#
		#	}
		#	print "====\n";


			$data .=sprintf

		"
		EQUB	&2A		\\ synchronisation byte
		EQUS	\"%s\"	\\ name
		EQUB	0		\\ name zero term
		EQUD	&%08X	\\ load address
		EQUD	&%08X	\\ exec address
		EQUW	&%04X		\\ block number
		EQUW	&%04X		\\ block length
		EQUB	&%02X		\\ flag
		EQUD	&%08X	\\ next file ptr
		EQUW	&%02X		\\ header crc
", $name_munged, $load, $exec, $blockno, $datlen, $flag, $DATA_OFFSET, (($hdrcrc & 0xFF00) >> 8) | (($hdrcrc & 0xFF) << 8);

		} else {

			$data .="
		EQUB	&23		\\ INTER BLOCK MARKER
"
		}


		if ($datlen) {
			my $i = 0;
			for my $c (@thisdat) {
				if (($i % 8) == 0) {
					$data .= "
			EQUB	";
				} else {
					$data .= ", ";
				}

				$data .= sprintf "&%02X", $c;
				$i++;
			}

			my $datacrc = crc(pack("C*", @thisdat));
			$data .= sprintf "
			EQUW	&%04X		\\DATA CRC
				", (($datacrc & 0xFF00) >> 8) | (($datacrc & 0xFF) << 8);
		}

		$blockno++;

	}

	if ($DATA_OFFSET >= 0xBFFF) {
		printf STDERR "ROM full : %08X\n", $DATA_OFFSET;
		return 0;
	} else {
		return 1;
	}
}

sub crc($) {
	my ($dat) = @_;
	my $crc = 0;

	for my $c (split //, $dat) {
		my $n = ord($c);

		$crc ^= $n << 8;
		for (my $i=0; $i < 8; $i++) {
			if ($crc & 0x8000) {
				$crc ^= 0x0810;
				$crc = ( ($crc << 1) + 1 ) & 0xFFFF;
			} else {
				$crc = ($crc << 1) & 0xFFFF;
			}
		}
	}

	return $crc;
}
