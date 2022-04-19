# (c) Copyright 2006-2008, 2010. CodeWeavers, Inc.
package CXCDE;
use warnings;
use strict;

use CXUtils;
use CXLog;

sub new($)
{
    my ($class, $filename)=@_;

    my $self={ filename    => $filename,
               actions     => {},
               attributes  => {},
               criteria    => {},
               created_by  => {}
             };
    bless $self, $class;

    return $self if (!-e $filename);

    cxlog("Reading '$self->{filename}'\n");
    my $fh;
    if (!open($fh, "<", $self->{filename}))
    {
        cxerr("unable to open '$self->{filename}' for reading: $!\n");
        return 0;
    }

    my $count=0;
    my ($line, $blob, $ignore);
    foreach my $l (<$fh>)
    {
        $count++;
        chomp $l;
        if (defined $line)
        {
            $l =~ s/^\s*//;
            $line.=$l;
        }
        else
        {
            $l =~ s/^\s*//;
            if ($l =~ /^\s*#\s*X-Created-By-([^= ]*)\s*=\s*(\S*)/)
            {
                my ($key, $list)=($1, $2);
                map { $self->{created_by}->{$key}->{$_}=1 } split /;+/, $list;
                next;
            }
            next if ($l =~ /^#/);
            next if ($l eq "");
            $line=$l;
        }
        # Apparently Solaris allows spaces after the EOL continuation backslash
        next if ($line =~ s/\\\s*$//);
        #cxlog("line=[$line]\n");

        if ($blob)
        {
            if ($line =~ /^{/)
            {
                # Nothing to do
            }
            elsif ($line =~ /^}/)
            {
                $blob=undef;
            }
            elsif ($line =~ /^([A-Z0-9_]+)\s+(.*)$/)
            {
                $blob->{$1}=$2;
                #cxlog(" key [$1]=[$2]\n");
            }
            else
            {
                cxwarn("$count: unknown type of action line '$line'\n");
            }
        }
        elsif ($ignore)
        {
            if ($line =~ /^}/)
            {
                $ignore=undef;
            }
        }
        elsif ($line =~ /^ACTION\s+(\S+)\s*$/)
        {
            $blob={};
            $self->{actions}->{$1}=$blob;
            #cxlog("action [$1]\n");
        }
        elsif ($line =~ /^DATA_ATTRIBUTES\s+(\S+)\s*$/)
        {
            $blob={};
            $self->{attributes}->{$1}=$blob;
            #cxlog("attributes [$1]\n");
        }
        elsif ($line =~ /^DATA_CRITERIA\s+(\S+)\s*$/)
        {
            $blob={};
            $self->{criteria}->{$1}=$blob;
            #cxlog("criteria [$1]\n");
        }
        elsif ($line =~ /^\{/)
        {
            $ignore=1 if (!$blob);
        }
        elsif ($line =~ /^set\s/)
        {
            # We silently ignore those
        }
        else
        {
            cxwarn("$count: unknown type of line '$line'\n");
        }
        $line=undef;
    }
    close($fh);
    # For debug...
    # map { cxlog("  $_\n"); } keys %{$self->{actions}};

    return $self;
}

sub save($)
{
    my ($self)=@_;
    my %cname=(actions    => "ACTION",
               attributes => "DATA_ATTRIBUTES",
               criteria   => "DATA_CRITERIA"
              );

    my $dir=cxdirname($self->{filename});
    if (!cxmkpath($dir))
    {
        cxerr("unable to create the '$dir' directory: $@\n");
        return 0;
    }
    my $fh;
    if (!open($fh, ">", $self->{filename}))
    {
        cxerr("unable to open '$self->{filename}' for writing: $!\n");
        return 0;
    }

    cxlog("CXMenuCDE writing to '$self->{filename}'\n");
    foreach my $category ("attributes", "criteria", "actions")
    {
        foreach my $name (sort keys %{$self->{$category}})
        {
            print $fh "$cname{$category} $name\n";
            print $fh "{\n";
            my $data=$self->{$category}->{$name};
            foreach my $key (sort keys %$data)
            {
                print $fh "    $key ", (' ' x (16-length($key))), "$data->{$key}\n";
            }
            print $fh "}\n";
            print $fh "\n";
        }
    }

    foreach my $key (sort keys %{$self->{created_by}})
    {
        my @list=keys %{$self->{created_by}->{$key}};
        print $fh "# X-Created-By-$key=", join(";", sort @list), "\n";
    }

    close($fh);
    return 1;
}

sub is_empty($)
{
    my ($self)=@_;
    return 0 if (%{$self->{actions}});
    return 0 if (%{$self->{attributes}});
    return 0 if (%{$self->{criteria}});
    return 1;
}

sub dump($)
{
    my ($self)=@_;

    cxlog("filename=$self->{filename}\n");
    foreach my $category ("criteria", "attributes", "actions")
    {
        cxlog("$category\n");
        foreach my $name (sort keys %{$self->{$category}})
        {
            cxlog("  $category $name\n");
            my $data=$self->{$category}->{$name};
            foreach my $key (sort keys %$data)
            {
                cxlog("    $key=$data->{$key}\n");
            }
        }
    }
}

return 1;
