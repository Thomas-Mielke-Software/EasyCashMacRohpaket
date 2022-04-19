# (c) Copyright 2005-2008, 2010, 2014. CodeWeavers, Inc.
package CXAssocCheck;
use warnings;
use strict;

use CXLog;
use CXUtils;


sub detect($$$$)
{
    my ($class, $cxoptions)=@_;

    my $self={
        tag             => $cxoptions->{tag},
        desktopdata     => $cxoptions->{desktopdata},
        ro_desktopdata  => $cxoptions->{ro_desktopdata},
    };
    bless $self, $class;
    return ($self);
}

sub id($)
{
    return "CXAssocCheck/";
}

sub preinstall($$)
{
    # Nothing to do
    return 1;
}

sub get_script_base($$$)
{
    my ($self, $massoc)=@_;
    return "/cxassoc/Scripts/$self->{tag}:$massoc->{id}";
}

sub install($$)
{
    my ($self, $massoc)=@_;
    if (!$massoc->{command})
    {
        # Don't allow the creation of an association with no command
        # as it would look broken to the user.
        cxerr("'$massoc->{ref_eassoc}->{id}' must have a command\n");
        return -1; # Fatal error
    }

    my $script=$self->get_script_base($massoc);
    $massoc->{cmdbase}=$script;

    $script="$self->{desktopdata}$script";
    cxlog("Creating '$script'\n");

    my $scriptdir=cxdirname($script);
    if (!cxmkpath($scriptdir))
    {
        cxerr("unable to create '$scriptdir': $@\n");
        return -1; # Fatal error
    }

    if ($self->{ro_desktopdata} and -f $script and -x _)
    {
        # Assume the script has already been created
    }
    elsif (open(my $fh, ">", $script))
    {
        print $fh "#!/bin/sh\n";
        print $fh "exec $massoc->{command} \"\$\@\"\n";
        close($fh);
    }
    else
    {
        cxerr("unable to open '$script' for writing: $!\n");
        return -1; # Fatal error
    }
    chmod(0777 & ~umask(), $script);

    # Avoid quoting the command if we can as this confuses Mozilla 1.7.8!
    $massoc->{command}=($script =~ /[\x01-\x1f\x80-\xff \$"'`<>|#&;%]/) ?
                       shquote_string($script) :
                       $script;
    return 1;
}

sub query($$)
{
    my ($self, $massoc)=@_;
    return {} if (!$massoc);

    # Don't report the CXAssocCheck install status
    # but set cmdbase so query can verify it.
    $massoc->{cmdbase}=$self->get_script_base($massoc);

    return "";
}

sub get_files($$)
{
    my ($self, $massoc)=@_;

    # Set the cmdbase so the other modules can use it to identify associations
    my $script=$self->get_script_base($massoc);
    $massoc->{cmdbase}=$self->get_script_base($massoc);

    # The script is inside the CrossOver bottle
    # but would not normally get packaged.
    $script="$self->{desktopdata}$script";
    return -f $script ? [$script] : [];
}

sub uninstall($$)
{
    my ($self, $massoc)=@_;

    # Set the cmdbase so the other modules can use it to identify associations
    my $script=$self->get_script_base($massoc);
    $massoc->{cmdbase}=$script;

    $script="$self->{desktopdata}$script";
    if (!$self->{ro_desktopdata} and -f $script)
    {
        cxlog("Deleting '$script'\n");
        if (!unlink $script)
        {
            cxwarn("unable to delete '$script': $!\n");
        }
    }

    return 1;
}

sub removeall($$)
{
    my ($self, $pattern)=@_;
    return 1 if ($pattern eq "legacy");
    return 1 if ($self->{ro_desktopdata});

    if ($self->{tag} and $self->{tag} =~ /^$pattern/)
    {
        my $dir="$self->{desktopdata}/cxassoc/Scripts";
        if (-d $dir)
        {
            cxlog("Deleting the '$dir' directory\n");
            require File::Path;
            if (!File::Path::rmtree($dir))
            {
                cxerr("unable to delete the '$dir' directory: $!\n");
            }
        }
        CXUtils::garbage_collect_subdirs($self->{desktopdata}, "/cxassoc", 1);
    }
    else
    {
        require CXBottle;
        CXBottle::removeall_desktopdata_dirs($pattern, "/cxassoc/Scripts");
    }
    return 1;
}

sub finalize($)
{
    my ($self)=@_;
    if (!$self->{ro_desktopdata} and defined $self->{desktopdata})
    {
        CXUtils::garbage_collect_subdirs($self->{desktopdata},
                                         "/cxassoc/Scripts", 1);
    }
    return 1;
}

return 1;
