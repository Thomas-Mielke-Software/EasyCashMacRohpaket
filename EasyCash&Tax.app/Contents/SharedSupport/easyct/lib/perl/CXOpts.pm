# (c) Copyright 2002-2003, 2006, 2010. CodeWeavers, Inc.
package CXOpts;
use warnings;
use strict;

sub new($;$)
{
    my ($class, $flags)=@_;
    my $self={flags   => {},
              options => {}};
    bless $self, $class;
    $self->add_flags($flags) if (defined $flags);
    return $self;
}

# Supported flags:
#   stop_on_unknown = 0 | 1
#      If set, stop option processing without generating an error when
#      encountering an unknown option. Otherwise an error is generated.
#
#   stop_on_non_option = 0 | 1
#      Stop option processing without generating an error when
#      encountering a non-option. Otherwise an error is generated.
#
sub add_flags($$)
{
    my ($self, $flags)=@_;
    foreach my $arg (@$flags)
    {
        my ($flag,$value)=split /=/,$arg;
        $value=1 if (!defined $value);
        $self->{flags}->{$flag}=$value;
    }
}

# Define the options to be recognized by 'parse'.
#
#   add_options(['host=s'  => \$host,
#                'user=s'  => \$user,
#                'verbose!' => \$verbose
#               ]);
#
# If the command-line to the script is:
#
#         foo --host www.codeweavers.com --verbose
#
# After the call to parse(), $host is set to
# "www.codeweavers.com" and $verbose is set to 1.
#
#
sub add_options($$)
{
    my ($self, $options)=@_;
    while (@$options)
    {
        my $decl=shift @$options;
        my $ref=shift @$options;
        last if (!defined $ref);

	$decl =~ /([^!=]*)(\!)?(?:=(.*))?$/;
        my $names=$1;
        my $no=defined $2;
	my $type=$3 || "";
        my $opt={type => $type,
                 no   => $no,
                 ref  => $ref
                };
        if ($names eq "")
        {
	    $self->{options}->{""}=$opt;
        }
        else
        {
            foreach my $name (split /\|/,$names)
            {
                $self->{options}->{$name}=$opt;
            }
        }
    }
}

# Purpose:   Parse @ARGV a la Getopt::Long (but a watered-down
#            version)
#
# Each 'opt' specifies a possible option, which should start
# with '--' or '-' on the command line. To indicate that 'opt' takes
# a string argument, specify 'opt=s'; otherwise, 'opt' is
# assumed to be a boolean flag. To indicate that an option can appear
# multiple times, append '@' to its type specifier and its values will be
# returned as an array reference.
#
# Option processing stops if '--' appears by itself on the command-line,
# or a non-option string is found.
#
# Returns:   "" if successful, an error message otherwise
sub parse($;$)
{
    my ($self)=@_;
    my $argv=$_[1] || \@ARGV;

    # And now process the command line arguments
    while (1)
    {
        last if (!@$argv);
        my $arg=@$argv[0];

        # terminate at the first non-option
        if ($arg eq "-" or $arg !~ s/^--?//)
        {
            return "" if ($self->{flags}->{stop_on_non_option});
            return "unexpected argument '@$argv[0]'";
        }
        my $no=($arg =~ s/^no-//);
        $arg=~ s/=(.*)$//;
        my $value=$1;

        my $opt=$self->{options}->{$arg};
        if (!defined $opt)
        {
            if (@$argv[0] eq "--")
            {
                shift @$argv;
                return "";
            }
            return "" if ($self->{flags}->{stop_on_unknown});
            return "unknown '@$argv[0]' option";
        }
        $arg=shift @$argv;

        my $ref=$opt->{ref};
        if (!$opt->{type})
        {
            if (defined $value)
            {
                return "unexpected value for '$arg'";
            }
            if ($no)
            {
                $$ref=0;
            }
            else
            {
                $$ref++;
            }
            last if ($arg eq "--");
        }
        elsif ($opt->{type} eq "s@")
        {
            if (!defined $value)
            {
                if (!@$argv)
                {
                    return "missing value for $arg";
                }
                $value=shift @$argv;
            }
            push @{$$ref}, $value;
        }
        else
        {
            if (defined $opt->{count})
            {
                return "$arg can only be specified once";
            }
            if (!defined $value)
            {
                if (!@$argv)
                {
                    return "missing value for $arg";
                }
                $value=shift @$argv;
            }
            $opt->{count}=1;
            $$ref=$value;
        }
    }
    return "";
}

return 1;
