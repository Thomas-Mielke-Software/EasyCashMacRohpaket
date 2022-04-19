# (c) Copyright 2005, 2010, 2014. CodeWeavers, Inc.
package CXAssocDebian;
use warnings;
use strict;

use CXLog;
use CXUtils;
use CXAssocMcap;
use base "CXAssocMcap";


#####
#
# Main
#
#####

sub read_mailcap($)
{
    my ($self)=@_;
    if (!$self->{rwmcap})
    {
        cxlog("Reading '$self->{mailcap}'\n");
        $self->{rwmcap}=CXRWBlob->new($self->{tag}, $self->{mailcap},
                                      "mailcap", $self->{multiline});
    }
    return $self->{rwmcap};
}

sub detect($$$$)
{
    my ($class, $cxoptions, $cxconfig, $gui_info)=@_;
    return () if (!$gui_info->{debian_mime_on} or
                  !$gui_info->{debian_preferred_assoc} or
                  # Debian associations are for root only
                  $> != 0);

    my $self=CXAssocMcap->new("deb", $cxoptions, $cxconfig, $gui_info);
    $self->{assoc} = "$cxoptions->{destdir}$gui_info->{debian_preferred_assoc}";
    $self->{mailcap} = "$self->{assoc}/cxassoc-$self->{tag}" if (defined $self->{tag});
    bless $self, $class;
    return ($self);
}

sub id($)
{
    my ($self)=@_;
    my $id="CXAssocDebian/$self->{assoc}";
    $id =~ s%/+%/%g;
    return $id;
}

sub get_association_files($$$$)
{
    my ($self, $massoc, $adata, $state)=@_;
    return -f $self->{mailcap} ? [$self->{mailcap}] : [];
}

sub get_files($$)
{
    my ($self, $massoc)=@_;
    return $self->action($self->{mimes}, $massoc, "getfiles");
}

sub removeall($$)
{
    my ($self, $pattern)=@_;
    $self->{mimes}->removeall($self->{domain}, $pattern);

    if ($pattern eq "legacy")
    {
        $pattern="^" . CXUtils::get_product_id() . "\$";
    }
    else
    {
        $pattern="^cxassoc-$pattern";
    }
    CXUtils::delete_files($self->{assoc}, $pattern);

    return 1;
}

sub finalize($)
{
    my ($self)=@_;

    my $rc=$self->SUPER::finalize();
    cxsystem("update-mime") if (!$self->{destdir});
    return $rc;
}

return 1;
