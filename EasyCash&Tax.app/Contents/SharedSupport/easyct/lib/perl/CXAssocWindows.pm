# (c) Copyright 2005-2006, 2010. CodeWeavers, Inc.
package CXAssocWindows;
use warnings;
use strict;

use CXLog;
use CXUtils;


sub detect($$$$)
{
    my ($class, $cxoptions, $cxconfig, $gui_info)=@_;

    my $self={};
    bless $self, $class;
    return ($self);
}

sub id($)
{
    return "CXAssocWindows/";
}

sub preinstall($$)
{
    my ($self, $massoc)=@_;

    foreach my $ext (keys %{$massoc->{mime}->{exts}})
    {
        $massoc->{all_exts}->{$ext}=1;
    }
    return 1;
}

sub install($$)
{
    my ($self, $massoc)=@_;
    return 1 if ($massoc->{type} ne "windows");

    if ($massoc->{command} ne "")
    {
        cxwarn("'windows' associations cannot have a command. Overriding the command\n");
    }
    my $allowed=join(":", map { ".$_" } sort keys %{$massoc->{all_exts}});
    my @cmd=(shquote_string("$ENV{CX_ROOT}/bin/cxstart"),
             "--bottle", shquote_string($ENV{CX_BOTTLE}),
             "--untrusted", "--wait-children",
             "--start-only", shquote_string($allowed));
    my $class=$massoc->{appid};
    if ($class)
    {
        push @cmd, "--start-class", shquote_string(demangle_string($class));
    }
    else
    {
        my $default=$massoc->{mime}->{real} ?
                    $massoc->{mime}->{mimetype} :
                    ".$massoc->{ref_eassoc}->{ext}";
        push @cmd, "--start-default", shquote_string($default);
    }
    my $verb=$massoc->{verb};
    if ($verb)
    {
        push @cmd, "--start-verb", shquote_string(demangle_string($verb));
    }
    $massoc->{command}=join(" ", @cmd);
    $massoc->{genericname}="Windows Association (CrossOver)";
    return 1;
}

sub query($$)
{
    # Don't report the CXAssocWindows install status
    my ($self, $massoc)=@_;
    return {} if (!$massoc);
    return "";
}

sub get_files($$)
{
    my ($self, $massoc)=@_;
    # No file gets created so there is nothing to report
    return [];
}

sub uninstall($$)
{
    # Nothing to uninstall
    return 1;
}

sub removeall($$)
{
    # Nothing to remove
    return 1;
}

sub finalize($)
{
    # Nothing to finalize
    return 1;
}

return 1;
