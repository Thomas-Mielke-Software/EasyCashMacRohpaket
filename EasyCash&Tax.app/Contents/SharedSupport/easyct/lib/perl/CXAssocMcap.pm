# (c) Copyright 2005-2008, 2010, 2014. CodeWeavers, Inc.
package CXAssocMcap;
use warnings;
use strict;

use CXLog;
use CXMimeMcap;
use CXAssoc;
use base "CXAssoc";


#####
#
# Association creation and deletion
#
#####

sub create_association($$$$)
{
    my ($self, $massoc, $adata, $extensions)=@_;
    if ($massoc->{mode} ne "default")
    {
        return $self->delete_association($massoc, $adata);
    }
    my $rwmcap=$self->read_mailcap();

    # Use {default_mimes} as we can only set default associations
    foreach my $mimetype (keys %{$adata->{default_mimes}})
    {
        cxlog("Associating '$massoc->{id}' with '$mimetype'\n");
        my $cxassoc=$rwmcap->add("mailcap", $mimetype);

        CXAssoc::setup_from_best_eassoc($massoc);
        my $name=$massoc->{appname};
        if ($massoc->{verb})
        {
            CXAssoc::compute_verb_name($massoc);
            if ($massoc->{verbname})
            {
                # Mailcap does not have the notion of a keyboard shortcut for
                # associations.
                $name.=" (" . CXAssoc::remove_accelerators($massoc->{verbname}) . ")";
            }
        }
        # Notes:
        # - The combination of '.=', the above ampersand substitution,
        #   UTF-8 accents, LANG=en_US.UTF-8 and CX_TAGALL=1 is causing
        #   perl 5.8.0 to segfault on Red Hat 8.0! So we avoid '.=' here.
        # - We should probably convert the name to the system
        #   encoding. But then I have not found a single application that
        #   uses it so there's no telling what is really allowed.
        # - Escape '%' and ';' as per RFC 1524.
        $name="$name (" . $self->id() . ")" if ($ENV{CX_TAGALL});
        my $cmd=$massoc->{command};
        $cmd =~ s/([%;])/\\$1/g;

        # Recreate the association from scratch...
        $cxassoc->{fields}={
            "description=" => $name,
            ""             => "$cmd '\%s'"
        };
        # FIXME: Depending on the verb we could try to take advantage of the
        # edit and print fields mentioned by RFC 1524.
        delete $cxassoc->{lines};
        delete $cxassoc->{created_by};

        my @extlist=keys %$extensions;
        if (@extlist == 1)
        {
            # If there is one unambiguous extension, then try to make sure
            # the email client's temporary file will use that extension.
            $cxassoc->{fields}->{"nametemplate="}="\%s.$extlist[0]";
        }
        $rwmcap->modified($cxassoc);
    }

    return 1;
}

sub query_association($$$$)
{
    my ($self, $massoc, $adata, $state)=@_;
    my $rwmcap=$self->read_mailcap();

    # Escape '%' and ';' as per RFC 1524.
    my $cmdbase=$massoc->{cmdbase};
    $cmdbase =~ s/([%;])/\\$1/g;
    my $rc=$state;
    foreach my $mimetype (keys %{$adata->{default_mimes}})
    {
        cxlog("Querying association with '$mimetype'\n");
        my $cxassoc=$rwmcap->get($mimetype);
        return $state if (!$cxassoc);

        my $cmd=$cxassoc->{fields}->{""} || "";
        return $state if ($cmd !~ /\Q$cmdbase\E(?:[^:]|$)/);
        $rc="default";
    }
    # We cannot check that the MAssoc is not associated to more MIME types
    # than it should because its command might be the generic script which
    # is shared by multiple MAssocs

    return $rc;
}

sub delete_association($$$)
{
    my ($self, $massoc, $adata)=@_;
    my $rwmcap=$self->read_mailcap();

    # Escape '%' and ';' as per RFC 1524.
    my $cmdbase=$massoc->{cmdbase};
    $cmdbase =~ s/([%;])/\\$1/g;
    foreach my $mimetype (keys %{$adata->{all_mimes}})
    {
        my $cxassoc=$rwmcap->get($mimetype);
        if ($cxassoc)
        {
            my $cmd=$cxassoc->{fields}->{""} || "";
            if ($cmd =~ /\Q$cmdbase\E/)
            {
                cxlog("Deleting association with '$mimetype'\n");
                $rwmcap->remove($cxassoc);
            }
        }
    }
    return 1;
}


#####
#
# Main
#
#####

sub new($$$$$)
{
    my ($class, $domain, $cxoptions, $cxconfig, $gui_info)=@_;
    return () if (!$gui_info->{mailcap_on});

    my $self={
        tag            => $cxoptions->{tag},
        destdir        => $cxoptions->{destdir},
        mimes          => CXMimeMcap->get($domain, $cxoptions, $gui_info),
        do_assoc       => 1,
        domain         => $domain
    };
    $self->{multiline}=($gui_info->{mailcap_global_mime} ne $gui_info->{mailcap_preferred_mime});
    bless $self, $class;
    return $self;
}

sub preinstall($$)
{
    my ($self, $massoc)=@_;
    return $self->{mimes}->collect_unix_extensions($massoc);
}

sub install($$)
{
    my ($self, $massoc)=@_;
    return $self->action($self->{mimes}, $massoc, "install");
}

sub query($$)
{
    my ($self, $massoc)=@_;

    if (!$massoc)
    {
        my $id=$self->id();
        return {default   => $id,
                mime      => $id,
                partial   => $id};
    }
    return $self->action($self->{mimes}, $massoc, "query");
}

sub uninstall($$)
{
    my ($self, $massoc)=@_;
    return $self->action($self->{mimes}, $massoc, "uninstall");
}

sub finalize($)
{
    my ($self)=@_;

    my $rc=$self->{mimes}->finalize();
    $rc&=$self->{rwmcap}->delete_or_save() if (defined $self->{rwmcap});
    return $rc;
}

return 1;
