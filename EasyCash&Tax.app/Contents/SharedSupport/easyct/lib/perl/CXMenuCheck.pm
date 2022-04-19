# (c) Copyright 2005, 2010, 2014. CodeWeavers, Inc.
package CXMenuCheck;
use warnings;
use strict;
use CXLog;
use CXMenu;

sub detect($$$$)
{
    my ($class)=@_;

    my $self={};
    bless $self, $class;
    return ($self);
}

sub id($)
{
    return "CXMenuCheck/";
}

sub install($$)
{
    my ($self, $components)=@_;

    my $menu=@$components[-1];
    if (!$menu->{is_dir} and !$menu->{command})
    {
        # Don't allow the creation of a menu with no command
        # as it would look broken to the user.
        cxerr("'$menu->{rawpath}' must have a command\n");
        return -1; # Fatal error
    }
    elsif ($menu->{is_dir} and $menu->{command})
    {
        cxerr("folder '$menu->{rawpath}' cannot have a command. Ignoring it\n");
        $menu->{command}="";
        return 0;
    }
    # Provide a default for the icon root
    $menu->{icon_root}="$ENV{CX_ROOT}/share/icons" if ($menu->{type} eq "raw");
    return 1;
}

sub query($$)
{
    # Don't report the CXMenuCheck install status
    return ("", "");
}

sub get_files($$)
{
    my ($self, $components)=@_;

    # Provide a default for the icon root
    my $menu=@$components[-1];
    $menu->{icon_root}="$ENV{CX_ROOT}/share/icons" if ($menu->{type} eq "raw");

    # No file gets created so there is nothing to report
    return [];
}

sub uninstall($$)
{
    # Nothing needs checking
    return 1;
}

sub removeall($$)
{
    # Nothing needs checking
    return 1;
}

sub finalize($)
{
    # Nothing to finalize
    return 1;
}

return 1;
