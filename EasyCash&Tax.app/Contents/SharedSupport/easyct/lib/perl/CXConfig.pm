# (c) Copyright 2002-2010. CodeWeavers, Inc.
package CXConfig;
use warnings;
use strict;

use CXLog;
use CXUtils;


#
# The CXSection class
#
{
    package CXSection;

    sub new($$)
    {
        my ($class, $name)=@_;
        my $self={
            name => $name,
            field_list => [],
            fields => {}
        };
        return bless($self, $class);
    }

    sub get($$;$)
    {
        my ($self, $key, $default)=@_;
        $key =~ tr/A-Z/a-z/;
        my $value=$self->{fields}->{$key};
        $value=$default if (!defined $value);
        return $value;
    }

    sub get_name($)
    {
        my ($self)=@_;
        return $self->{name};
    }

    sub get_field_list($)
    {
        my ($self)=@_;
        return $self->{field_list};
    }

    sub get_fields($)
    {
        my ($self)=@_;
        return $self->{fields};
    }
}


#
# The CXConfig class
#

sub new($@)
{
    my $class=shift @_;

    my $self={};
    bless $self, $class;

    foreach my $file (@_)
    {
        $self->read($file);
    }
    return $self;
}

sub read($$)
{
    my ($self, $config_file)=@_;

    my $fh;
    return undef if (!open($fh, $config_file));
    cxlog("CXConfig->read($config_file)\n");
    push @{$self->{filenames}}, $config_file;

    my $section="";
    my $current;
    while (<$fh>)
    {
        chomp;
        s/^\s*//;
        s/^;.*$//;
        next if ($_ eq "");
        s/\s*$//;

        if (/^\[(.*)\]\s*(?:;[^\]]*)?$/)
        {
            # New section
            my $name=$1;
            my $key=$name;
            $key =~ tr/A-Z/a-z/;
            $current=$self->{sections}->{$key};
            if (!defined $current)
            {
                $current=CXSection->new($name);
                $self->{sections}->{$key}=$current;
            }
            next;
        }
        if (!defined $current)
        {
            # Ignore garbage at the beginning of the file
            next;
        }

        my ($name,$value);
        if (/^\s*\"((?:[^\\\"]|\\.)*)\"\s*=\s*\"((?:[^\\\"]|\\.)*)\"(?:\s*;.*)?\r?$/)
        {
            # This is a field in the following format:
            #    "Name"="Value"
            # or "Name" = "Value" ; comment
            # or ;"Name" = "Value"
            # where Name and Value are escaped strings which can
            # contain backslashes and quotes.
            $name=unescape_string($1);
            $value=unescape_string($2);
        }
        elsif (/^\s*([^=;][^=]*?)(?:\s*=\s*)(.*?)\s*\r?$/)
        {
            # This is a field in the following format:
            #    Name=Value
            # or Name = Value ; also part of the value
            # or ;Name = Value
            # Note that this intentionally also matches
            #    Name="Value"
            # where the quotes are part of the value.
            $name=$1;
            $value=$2;
        }
        if (!defined $name or !defined $value)
        {
            # This must be garbage
            next;
        }
        my $key=$name;
        $key =~ tr/A-Z/a-z/;
        if ($value eq "<undef>")
        {
            delete $current->{fields}->{$key};
            my $list=$current->{field_list};
            my $count=@$list;
            for (my $i=0; $i<$count; $i++)
            {
                if ($list->[$i] eq $name)
                {
                    splice @$list, $i, 1;
                    last;
                }
            }
        }
        else
        {
            if (!exists $current->{fields}->{$key})
            {
                push @{$current->{field_list}}, $name;
            }
            $current->{fields}->{$key}=$value;
        }
    }
    close($fh);
    return 1;
}

sub get_filenames($)
{
    my ($self)=@_;
    return $self->{filenames};
}

sub get_section_keys($)
{
    my ($self)=@_;
    return keys %{$self->{sections}};
}

sub get_section_names($)
{
    my ($self)=@_;
    return map { $self->{sections}->{$_}->{name} } keys %{$self->{sections}};
}

sub get_section($$)
{
    my ($self, $section)=@_;
    $section =~ tr/A-Z/a-z/;
    return $self->{sections}->{$section};
}

sub get($$$;$)
{
    my ($self, $section, $key, $default)=@_;
    $section =~ tr/A-Z/a-z/;
    $key =~ tr/A-Z/a-z/;
    my $value=$self->{sections}->{$section}->{fields}->{$key};
    $value=$default if (!defined $value);
    return $value;
}

return 1;
