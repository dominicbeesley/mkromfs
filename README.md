# mkromfs
perl script to make a romfs style ROM.

# Requirements

## BeebAsm
This will be used to assemble the generated assembler

## Perl
This is used to generate the assembler file


# Normal usage

mkromfs.pl --title=<rom title> --version=<rom version> --copy=<copyright> --output=<output> --noasm [file...]

--title         This is the title that will be given to the ROM and also a dummy 0 byte file will be
                generated with this name and shown with \*CAT

--version       A version number 0..255 for the ROM

--copy          A copyright message for the ROM this must start with "(C)"

--output        The output filename for the generated ROM or assembler

--noasm         If specified the ROM will not be assembled, instead the output will be the assembler
                for the ROM.

[file...]       The files to add to the ROM. The files will be added in the order that they are specified.
                If there is a file with a .inf extension with the same name it will be used to set the filename
                load, exec and access/lock attributes
                If the file specified ends with .inf then a matching file without the .inf extension will be
                used as the data file.
                If both are specifed then one will be skipped

# Changing the assembler template

mkromfs.pl --calcoffs

The assembler template handlesvc.asm is taken from the New Advanced User Guide. Should you wish to change the
service handler then you should run this to recalculate the data offset start and change the $DATA_OFFSET= line
near the start of the perl script.



