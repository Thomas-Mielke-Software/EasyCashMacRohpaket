# (c) Copyright 2005-2006, 2010, 2014. CodeWeavers, Inc.
package CXAssoc;
use warnings;
use strict;
use CXLog;
use CXUtils;


#####
#
# Locating / computing the icon and description
#
#####

sub get_icon_dir()
{
    return "$ENV{WINEPREFIX}/windata/Associations" if (defined $ENV{WINEPREFIX});
    return undef;
}

sub get_icon($)
{
    my ($icon)=@_;
    return undef if (($icon || "") eq "");
    return $icon if ($icon =~ m%^/%);

    my $icon_dir=get_icon_dir();
    return undef if (!defined $icon_dir);
    return "$icon_dir/$icon";
}

# Compute the 'best' icon and description for a MIME type or a 'MAssoc' object
# based on the corresponding cxassoc.conf entries (EAssocs). Best here is
# defined as:
#  - 'Default' EAssocs have a higher precedence than 'Alternative' EAssocs
#    which are themselves ahead of 'Mime' EAssocs.
#    'Ignore' EAssocs are ignored altogether.
#  - EAssocs corresponding to the default application for an extension are
#    given a higher precedence than other EAssocs.
#  - EAssocs are then sorted by extension and by application name.
sub setup_from_best_eassoc($)
{
    my ($object)=@_;
    return if (exists $object->{icon});

    my %mode_to_score=(
        default     => 0,
        alternative => 1,
        mime        => 2
    );

    my ($best_sortkey, $best_icon, $best_description, $best_infotip, $best_appname, $best_ext, $best_localize);
    $best_sortkey="9"; # An impossibly bad value
    foreach my $eassoc (values %{$object->{eassocs}})
    {
        next if ($eassoc->{mode} eq "ignore");
        my $current_sortkey=join(":",
                                 $mode_to_score{$eassoc->{mode}},
                                 ($eassoc->{id} =~ m%/% ? "2" : "1"),
                                 $eassoc->{id});
        if ($current_sortkey lt $best_sortkey)
        {
            $best_sortkey=$current_sortkey;
            # Always override the icon, even if undef, to avoid a mismatch
            # between the icon and the description/infotip/appname
            $best_icon=get_icon($eassoc->{icon});
            $best_description=$eassoc->{description};
            $best_infotip=$eassoc->{infotip};
            $best_appname=$eassoc->{appname};
            $best_ext=$eassoc->{ext};
            $best_localize=$eassoc->{localize};
        }
    }
    $object->{icon}=$best_icon || CXUtils::get_std_icon("crossover");
    $object->{description}=$best_description || "";
    $object->{infotip}=$best_infotip || "";
    $object->{appname}=$best_appname || "";
    $object->{ext}=$best_ext;
    $object->{localize}=$best_localize;
}


my $std_verb_names={
    ""        => "&Open",
    "edit"    => "&Edit",
    "install" => "&Install", # for the CrossOver associations
    "open"    => "&Open",
    "opennew" => "&Open",
    "play"    => "&Play",
    "preview" => "Pre&view",
    "print"   => "&Print",
    "restore" => "&Restore", # for the CrossOver associations
    "run"     => "&Run",     # for the CrossOver associations
};
sub std_verb_names()
{
    return $std_verb_names;
}

sub compute_verb_name($)
{
    my ($massoc)=@_;
    return if (exists $massoc->{verbname});

    my ($verbname, $stdverbname);
    cxlog("compute_verb_name($massoc->{id}):\n");
    foreach my $eassoc (values %{$massoc->{eassocs}})
    {
        next if ($eassoc->{mode} =~ /^(ignore|mime)$/);
        if (!defined $verbname)
        {
            $verbname=$eassoc->{verbname};
            $stdverbname=$eassoc->{stdverbname};
            cxlog("  first name=$verbname\n");
        }
        elsif ($verbname ne $eassoc->{verbname})
        {
            cxlog("  mismatch=$eassoc->{verbname}\n");
            $verbname="";
            $stdverbname=undef;
            last;
        }
    }
    $massoc->{verbname}=$verbname;
    $massoc->{stdverbname}=$stdverbname;
}

# Removes the ampersands that denote accelerator keys. Note that while
# (normally) only the first one denotes an accelerator key, they all need to
# be removed unless doubled.
sub remove_accelerators($)
{
    my ($string)=@_;
    $string =~ s/&(.)/$1/g;
    return $string;
}


#####
#
# Common MIME handling routines for subclasses
#
#####

sub init_mime_handler($$)
{
    my ($self, $cxoptions)=@_;
    $self->{tag}            = $cxoptions->{tag};
    $self->{winexts}        = $cxoptions->{winexts};
    $self->{winmimes}       = $cxoptions->{winmimes},
    $self->{mimealiases}    = $cxoptions->{mimealiases};
    $self->{mimeignorelist} = $cxoptions->{mimeignorelist};
    $self->{massocs}        = $cxoptions->{massocs};

}

sub mdb_add_mime($$$)
{
    my ($self, $mimetype, $exts)=@_;
    cxlog("adding $mimetype [", ($exts?join(",", @$exts):"<undef>"), "]\n");
    my $mdb_mime=$self->{mdb_mimes}->{$mimetype};
    if (!$mdb_mime)
    {
        $mdb_mime={
            mime     => $mimetype,
            exts     => {},
            ext_list => []
        };
        $self->{mdb_mimes}->{$mimetype}=$mdb_mime;
    }
    foreach my $ext (@$exts)
    {
        next if ($mdb_mime->{exts}->{$ext});
        $mdb_mime->{exts}->{$ext}=1;
        push @{$mdb_mime->{ext_list}}, $ext;

        my $mdb_ext=$self->{mdb_exts}->{$ext};
        if (!$mdb_ext)
        {
            $mdb_ext={};
            $self->{mdb_exts}->{$ext}=$mdb_ext;
        }
        $mdb_ext->{$mimetype}=$mdb_mime;
    }
}

sub mdb_has_mime($$)
{
    my ($self, $mimetype)=@_;
    return exists $self->{mdb_mimes}->{$mimetype};
}

sub mdb_get_mimes_from_ext($$)
{
    my ($self, $ext)=@_;
    my $mdb_ext=$self->{mdb_exts}->{$ext};
    return () if (!$mdb_ext);
    return keys %$mdb_ext;
}

sub ignore_mime_alias($$$$)
{
    my ($self, $massoc, $adata, $unix_mt)=@_;

    return 0 if ($adata->{action} eq "uninstall");
    return 1 if ($self->{mimeignorelist}->{$unix_mt});

    # Two massocs may map to the same MIME type. If that happens,
    # associate only once to avoid having duplicate 'Open with...'
    # entries.
    my $mangled=mangle_string($unix_mt);
    my $massocid=$massoc->{id};
    $massocid =~ s/^[^:]+/$mangled/;
    my $am=$self->{massocs}->{$massocid};
    return 1 if ($am and $am->{mode} =~ /^(default|alternative)$/);

    # If we have this on Windows:
    #   video/x-ms-asf: asx
    #   audio/x-ms-wax: wax
    # But the following on Unix:
    #   audio/x-ms-asx: asx wax
    # So which massoc do we set as the audio/x-ms-asx default?
    # The asx one or the wax one?
    # To solve this conflict we take the first Windows
    # extension of the x-ms-asx MIME type (asx) and only use x-ms-asx
    # for the MIME type of that extension (x-ms-asf).
    foreach my $unix_ext (@{$self->{mdb_mimes}->{$unix_mt}->{ext_list}})
    {
        $unix_ext =~ tr/A-Z/a-z/;
        my $win_mime=$self->{winexts}->{$unix_ext};
        next if (!$win_mime);

        my $rc=($win_mime->{mimetype} eq $massoc->{mime}->{mimetype} ? 0 : 1);
        cxlog("  $unix_mt -> $unix_ext -> $win_mime->{mimetype} -> ", ($rc ? "ignored" : "added"), "\n");
        return $rc;
    }

    # If we have this on Windows:
    #   application/x-mspowerpoint: ppt
    #   application/vnd.ms-powerpoint: pot
    # And that application/mspowerpoint is an alias of these, then which
    # massoc gets to be the default for application/mspowerpoint?
    # The rule is that the first Windows MIME type in the sorted alias list
    # gets all the aliases.
    foreach my $alias (@{$self->{mimealiases}->{$unix_mt}})
    {
        $mangled=mangle_string($alias);
        $massocid=$massoc->{id};
        $massocid =~ s/^[^:]+/$mangled/;
        my $am=$self->{massocs}->{$massocid};
        if ($am and $am->{mode} =~ /^(default|alternative)$/)
        {
            my $rc=($alias eq $massoc->{mime}->{mimetype} ? 0 : 1);
            cxlog("  $unix_mt -> $alias -> alias ", ($rc ? "ignored" : "added"), "\n");
            return $rc;
        }
    }

    return 0;
}

sub get_mimes($$$$)
{
    my ($self, $massoc, $adata, $mode)=@_;

    my $win_mt=$massoc->{mime}->{mimetype};
    cxlog("  mode:            $win_mt | $adata->{action} | $mode\n");

    my $all_mimes;
    foreach my $win_ext (keys %{$adata->{$mode}})
    {
        my $found_mime;
        foreach my $unix_mt ($self->mdb_get_mimes_from_ext($win_ext))
        {
            # Whatever happens below, we found a Unix MIME type for this
            # extension, so don't create a CrossOver pseudo MIME type
            $found_mime=1;
            if (!$self->ignore_mime_alias($massoc, $adata, $unix_mt))
            {
                $all_mimes->{$unix_mt}=1;
            }
        }
        if (!$found_mime and !$self->{directmimes})
        {
            my $mimetype="application/x-crossover-$win_ext";
            $mimetype =~ tr/A-Z/a-z/;
            if (!$self->{mimeignorelist}->{$mimetype})
            {
                $all_mimes->{$mimetype}=1;
                $adata->{missing}->{$win_ext}=1;
            }
        }
    }
    if (CXLog::is_on())
    {
        cxlog("  all exts:        ", join(" ", sort keys %{$adata->{$mode}}), "\n");
        cxlog("  missing exts:    ", join(" ", sort keys %{$adata->{missing}}), "\n") if (!$self->{directmimes});
        cxlog("  extension mimes: ", join(" ", sort keys %$all_mimes), "\n");
    }

    $all_mimes->{$win_mt}=1;
    foreach my $mimetype (keys %{$massoc->{extramimes}})
    {
        next if ($self->{mimeignorelist}->{$mimetype});
        $all_mimes->{$mimetype}=1;
    }
    foreach my $mimetype (keys %$all_mimes)
    {
        my $aliases=$self->{mimealiases}->{$mimetype};
        foreach my $alias (@$aliases)
        {
            if (!$all_mimes->{$alias} and
                !$self->ignore_mime_alias($massoc, $adata, $alias))
            {
                $all_mimes->{$alias}=1;
            }
        }
    }
    if (CXLog::is_on())
    {
        cxlog("  after aliasing:  ", join(" ", sort keys %$all_mimes), "\n");
    }

    return $all_mimes;
}

sub collect_unix_extensions($$)
{
    my ($self, $massoc)=@_;

    $self->read_mime_db();

    my %done;
    foreach my $eassoc (values %{$massoc->{eassocs}})
    {
        next if ($eassoc->{mode} eq "ignore");
        my @exts=($eassoc->{ext});
        if ($self->{case_sensitive})
        {
            # Extensions are case-sensitive so we double each of them
            my $ext=$eassoc->{ext};
            $ext =~ tr/a-z/A-Z/;
            push @exts, $ext;
        }

        foreach my $win_ext (@exts)
        {
            my $mdb_ext=$self->{mdb_exts}->{$win_ext};
            next if (!$mdb_ext);

            foreach my $mdb_mime (values %{$mdb_ext})
            {
                next if ($done{$mdb_mime});
                $done{$mdb_mime}=1;
                next if ($self->{mimeignorelist}->{$mdb_mime->{mime}});
                map { $massoc->{all_exts}->{$_}=1 } @{$mdb_mime->{ext_list}};
            }
        }
    }
    return 1;
}


#####
#
# Core association creation engine
#
#####

sub compare_sets($$)
{
    my ($list, $ref_set)=@_;
    my %list_set;
    foreach my $item (@$list)
    {
        return 1 if (!$ref_set->{$item});
        $list_set{$item}=1;
    }
    foreach my $item (keys %$ref_set)
    {
        return -1 if (!$list_set{$item});
    }
    return 0;
}

sub action($$$$)
{
    my ($self, $mimes, $massoc, $action)=@_;

    $mimes->read_mime_db();

    # Build the list of relevant extensions
    my $adata={ action => $action };
    my $rc=$adata->{action} eq "getfiles" ? [] : 1;
    foreach my $eassoc (values %{$massoc->{eassocs}})
    {
        # FIXME: This is wrong. It breaks --query if the install mode is
        #        'ignore'.
        next if ($adata->{action} ne "uninstall" and $eassoc->{mode} eq "ignore");
        my @exts=($eassoc->{ext});
        if ($self->{case_sensitive})
        {
            # Extensions are case-sensitive so we double each of them
            my $ext=$eassoc->{ext};
            $ext =~ tr/a-z/A-Z/;
            push @exts, $ext;
        }

        if ($eassoc->{mode} eq "default")
        {
            map { $adata->{default}->{$_}=1 } @exts;
            map { $adata->{alt}->{$_}=1 } @exts;
            map { $adata->{mime}->{$_}=1 } @exts;
        }
        elsif ($eassoc->{mode} eq "alternative")
        {
            map { $adata->{alt}->{$_}=1 } @exts;
            map { $adata->{mime}->{$_}=1 } @exts;
        }
        else
        {
            $adata->{has_mimeonly}=1;
            map { $adata->{mime}->{$_}=1 } @exts;
        }
    }

    # Roundup related MIME types and find out which of our extensions
    # are not in the standard set
    $adata->{all_mimes}=$mimes->get_mimes($massoc, $adata, "mime");

    # Perform {action} on the CrossOver-specific 'Extension MIME types'
    my ($q_found_mime, $q_missing_mime);
    my %ext_done;
    foreach my $ext (keys %{$adata->{missing}})
    {
        # For case-sensitive association systems $ext may be uppercase or
        # lowercase. So convert it to lowercase so we start from a known
        # state and do this only once
        my $lower=$ext;
        $lower =~ tr/A-Z/a-z/;
        next if ($ext_done{$lower});
        $ext_done{$lower}=1;

        my $emimetype="application/x-crossover-$lower";
        if ($adata->{action} eq "uninstall")
        {
            $rc&=$mimes->untag_mime($self->{domain}, $massoc, $emimetype);
        }
        else
        {
            my $extensions;
            if ($self->{case_sensitive})
            {
                push @$extensions, $lower if ($adata->{missing}->{$lower});
                my $upper=$ext;
                $upper =~ tr/a-z/A-Z/;
                push @$extensions, $upper if ($adata->{missing}->{$upper});
            }
            else
            {
                push @$extensions, $lower;
            }
            my $emime=$massoc->{eassocs}->{$lower}->{emime};

            if ($adata->{action} eq "install")
            {
                $rc&=$mimes->create_mime($self->{domain}, $massoc, $emime, $emimetype, $extensions);
            }
            elsif ($adata->{action} eq "query")
            {
                if ($mimes->query_mime($self->{domain}, $massoc, $emimetype, $extensions))
                {
                    $q_found_mime=1;
                }
                else
                {
                    $q_missing_mime=1;
                }
            }
            else #$adata->{action} eq "getfiles"
            {
                push @$rc, @{$mimes->get_mime_files($self->{domain}, $massoc, $emimetype, $extensions)};
            }
        }
    }

    # Perform {action} on all involved 'real' MIME types
    foreach my $mimetype (keys %{$adata->{all_mimes}})
    {
        if ($adata->{action} eq "uninstall")
        {
            $rc&=$mimes->untag_mime($self->{domain}, $massoc, $mimetype);
        }
        else
        {
            my $extensions=[];
            my $mdb_mime=$mimes->{mdb_mimes}->{$mimetype};
            if ($self->{directmimes})
            {
                if ($massoc->{mime}->{mimetype} eq $mimetype)
                {
                    push @$extensions, keys %{$massoc->{mime}->{exts}};
                }
                elsif ($mdb_mime)
                {
                    $extensions=$mdb_mime->{ext_list};
                }
            }
            elsif ($mdb_mime)
            {
                if ($adata->{action} eq "query")
                {
                    $q_found_mime=1;
                }
                next;
            }

            if ($adata->{action} eq "install")
            {
                $rc&=$mimes->create_mime($self->{domain}, $massoc, $massoc->{mime}, $mimetype, $extensions);
            }
            elsif ($adata->{action} eq "query")
            {
                if ($mimes->query_mime($self->{domain}, $massoc, $mimetype, $extensions))
                {
                    $q_found_mime=1;
                }
                else
                {
                    $q_missing_mime=1;
                }
            }
            else # $adata->{action} eq "getfiles"
            {
                push @$rc, @{$mimes->get_mime_files($self->{domain}, $massoc, $mimetype, $extensions)};
            }
        }
    }
    if ($adata->{action} eq "query")
    {
        if (!$self->{directmimes} and !%{$adata->{missing}} and
            ($self->{mimeignorelist}->{$massoc->{mime}->{mimetype}} or
             $mimes->mdb_has_mime($massoc->{mime}->{mimetype})))
        {
            # We did not have to create any MIME type so the 'ignore'
            # and 'mime' states are indistinguishable. So return
            # whatever corresponds best to the install mode.
            $rc=($massoc->{mode} eq "ignore" ? "ignore" : "mime");
            cxlog("setting status = install mode = $rc\n");
        }
        else
        {
            return "ignore" if (!$q_found_mime);
            return "partial" if ($q_missing_mime);
            $rc="mime";
        }
    }
    return $rc if (!$self->{do_assoc});

    # If the install mode is 'mime' then switch action to
    # 'uninstall' so we delete the association if any
    if ($adata->{action} eq "install" and $massoc->{mode} eq "mime")
    {
        $adata->{action}="uninstall";
        # Compute the broadest list of MIME types from which we may have to
        # remove this association
        $adata->{all_mimes}=$mimes->get_mimes($massoc, $adata, "mime");
    }

    # Perform {action} on the association
    if ($adata->{action} eq "uninstall")
    {
        $rc&=$self->delete_association($massoc, $adata);
    }
    else
    {
        if ($adata->{has_mimeonly})
        {
            # Rebuild the MIME type list taking into account only the
            # 'alternative' and higher eassocs
            $adata->{all_mimes}=$mimes->get_mimes($massoc, $adata, "alt");
        }
        # Also build a MIME type list taking into account only the
        # 'default' eassocs. Note that this is needed now by association
        # systems that support the 'default' install mode but not the
        # 'alternative' one (CXAssocDebian for instance)
        $adata->{default_mimes}=$mimes->get_mimes($massoc, $adata, "default");

        if  ($adata->{action} eq "install")
        {
            $rc&=$self->create_association($massoc, $adata, $adata->{alternative});
        }
        elsif ($adata->{action} eq "query")
        {
            $rc=$self->query_association($massoc, $adata, $rc);
            return $rc if ($rc !~ /^(default|alternative)$/);
        }
        else # $adata->{action} eq "getfiles"
        {
            push @$rc, @{$self->get_association_files($massoc, $adata, $rc)};
        }
    }
    return $rc if (!$self->{do_default});

    # If the install mode is not 'default' then switch {action} to
    # 'uninstall' so we delete the default settings if any
    if ($adata->{action} eq "install" and $massoc->{mode} ne "default")
    {
        $adata->{action}="uninstall";
        # Compute the broadest list of MIME types from which we may have to
        # remove this association
        $adata->{all_mimes}=$mimes->get_mimes($massoc, $adata, "mime");
    }

    # And update the defaults
    if ($adata->{action} eq "uninstall")
    {
        $rc&=$self->delete_default($massoc);
    }
    else
    {
        if  ($adata->{action} eq "install")
        {
            $rc&=$self->create_default($massoc, $adata);
        }
        elsif ($adata->{action} eq "query")
        {
            $rc=$self->query_default($massoc, $adata, $rc);
        }
        else # $adata->{action} eq "getfiles"
        {
            push @$rc, @{$self->get_default_files($massoc, $adata, $rc)};
        }
    }
    return $rc;
}

return 1;
