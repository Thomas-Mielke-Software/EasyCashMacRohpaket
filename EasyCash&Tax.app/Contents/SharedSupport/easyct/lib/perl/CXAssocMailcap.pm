# (c) Copyright 2005, 2008, 2010, 2012, 2014. CodeWeavers, Inc.
package CXAssocMailcap;
use warnings;
use strict;

use CXLog;
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
    return () if (!$gui_info->{mailcap_on});

    my $self=CXAssocMcap->new("mcap", $cxoptions, $cxconfig, $gui_info);
    $self->{scope}   = $gui_info->{preferred_scope};
    $self->{mailcap} = "$cxoptions->{destdir}$gui_info->{mailcap_preferred_mailcap}";
    bless $self, $class;
    return ($self);
}

sub id($)
{
    my ($self)=@_;
    my $id="CXAssocMailcap/$self->{mailcap}";
    $id =~ s%/+%/%g;
    return $id;
}

sub get_files($$)
{
    # my ($self, $massoc)=@_;
    # The mailcap and mime.types files are not specific to this bottle
    # and thus must not be packaged with it.
    return [];
}

sub removeall($$)
{
    my ($self, $pattern)=@_;
    $self->{mimes}->removeall($self->{domain}, $pattern);

    $self->read_mailcap();
    if ($pattern eq "legacy")
    {
        foreach my $blob (@{$self->{rwmcap}->{blobs}})
        {
            if ($blob->{fields}->{"x-cxoffice"})
            {
                cxlog("Removing '$blob->{mimetype}' from mailcap\n");
                $self->{rwmcap}->remove($blob);
            }
        }

        my $productid=CXUtils::get_product_id();
        $pattern="^\\.$productid-app-\\d+\$";
        my @wrapper_dirs=("$ENV{CX_ROOT}/bin");
        if ($self->{scope} eq "private" and defined $ENV{HOME})
        {
            push @wrapper_dirs, "$ENV{HOME}/.$productid";
        }
        foreach my $dir (@wrapper_dirs)
        {
            next if (!-d $dir);
            if (!-w $dir)
            {
                cxlog("skipping read-only '$dir' directory\n");
                next;
            }
            CXUtils::delete_files($dir, $pattern);
        }
    }
    else
    {
        $pattern.="(?::|\\s)" if ($pattern =~ s/\$$//);
        foreach my $cxassoc (values %{$self->{rwmcap}->{mimetypes}})
        {
            my $cmd=$cxassoc->{fields}->{""} || "";
            if ($cmd =~ m%/cxassoc/Scripts/$pattern%)
            {
                $self->{rwmcap}->remove($cxassoc);
            }
        }
    }

    return 1;
}

return 1;
