# (c) Copyright 2006, 2008, 2010, 2014. CodeWeavers, Inc.
package CXAssocCDE;
use warnings;
use strict;

use CXLog;
use CXUtils;
use CXCDE;
use CXAssoc;
use base "CXAssoc";


#####
#
# MIME database helper functions
#
#####

sub read_mime_db($)
{
    my ($self)=@_;
    return if ($self->{read_mime_db});
    $self->{read_mime_db}=1;

    my @dirs=($self->{dtdir});
    push @dirs, $self->{global_dtdir} if ($self->{global_dtdir} ne $self->{dtdir});
    my $gdir="/usr/dt/appconfig/types/C";
    push @dirs, $gdir if ($self->{global_dtdir} ne $gdir);

    foreach my $dir (@dirs)
    {
        cxlog("dir $dir\n");
        my $dh;
        if (!opendir($dh, $dir))
        {
            cxlog("unable to open the '$dir' directory: $!\n");
            next;
        }
        foreach my $dentry (readdir $dh)
        {
            # Ignore CrossOver's MIME types
            next if ($dentry =~ /^(?:cxassoc|cxmenu)-/);

            # Ignore anything which is not a .dt CDE file
            next if ($dentry !~ /\.dt$/);
            $dentry="$dir/$dentry";
            next if (!-f $dentry);

            # Now we're left with the platform's native MIME types
            cxlog("Reading '$dentry'\n");
            my $dtfile=CXCDE->new($dentry);
            next if (!$dtfile);
            foreach my $criteria (values %{$dtfile->{criteria}})
            {
                my $mode=$criteria->{MODE} || "";
                #cxlog("mode=[$mode]\n");
                if ($mode !~ /(^|&)r?fr?(&|$)/)
                {
                    # This is not about files
                    next;
                }

                my $attr_name=$criteria->{DATA_ATTRIBUTES_NAME};
                if (!defined $attr_name)
                {
                    # No data attributes -> no MIME type
                    next;
                }
                my $attributes=$dtfile->{attributes}->{$attr_name};
                next if (!$attributes);

                my $mimetype=$attributes->{MIME_TYPE};
                next if (!defined $mimetype);

                my @exts;
                my $patterns=$criteria->{NAME_PATTERN} || "";
                foreach my $pattern (split /\|+/, $patterns)
                {
                    next if ($pattern !~ s/^\*\.//);
                    next if ($pattern =~ /[.*\\!]/);
                    if ($pattern !~ /\[/)
                    {
                        push @exts, $pattern;
                    }
                    elsif ($pattern =~ /^(?:[^[a-zA-Z]|\[[a-zA-Z][a-zA-Z]\])+$/)
                    {
                        my $recheck=$pattern;
                        $recheck =~ s/\[(.).\]/\\[(?:\L$1\E\U$1\E\|\U$1\E\L$1\E)\\]/g;
                        next if ($pattern !~ /^$recheck$/);

                        # Ok, this is just a case-insensitive extension
                        $pattern =~ s/\[(.).\]/\L$1\E/g;
                        push @exts, $pattern;
                    }
                }

                # Merge the extension lists of all MIME files together
                $self->mdb_add_mime($mimetype, \@exts);
            }
        }
        closedir($dh);
    }
}

sub read_dt_file($)
{
    my ($self)=@_;
    if (!$self->{dtfile})
    {
        $self->{dtfile}=CXCDE->new($self->{dtfilename});
    }
    return ($self->{dtfile} ? 1 : 0);
}


#####
#
# MIME type creation and deletion
#
#####

sub create_mime($$$$$$)
{
    my ($self, $domain, $massoc, $mime, $mimetype, $extensions)=@_;
    return 0 if (!$self->read_dt_file());

    my $attr_name=mangle_string($mimetype);
    if (!$self->{created}->{$mimetype})
    {
        cxlog("Creating '$mimetype'\n");

        # First the DATA_ATTRIBUTES section
        CXAssoc::setup_from_best_eassoc($mime);
        my $description=$mime->{description} || $mimetype;
        $description.=" (" . $self->id() . ")" if ($ENV{CX_TAGALL});

        # And recreate it from scratch to ensure it is up to date
        my $old_attr=$self->{dtfile}->{attributes}->{$attr_name} || {};
        my $attr={MIME_TYPE   => $mimetype,
                  TYPE_LABEL  => $mime->{description} || $mimetype,
                  ICON        => $mime->{icon}
                 };
        $attr->{NAME_TEMPLATE}="\%s.$mime->{ext}" if (defined $mime->{ext});
        $attr->{DESCRIPTION}=$mime->{infotip} if ($mime->{infotip} ne "");
        $attr->{IS_TEXT}="true" if ($mimetype =~ m!^text/!);
        $attr->{ACTIONS}=$old_attr->{ACTIONS} if (defined $old_attr->{ACTIONS});
        $self->{dtfile}->{attributes}->{$attr_name}=$attr;
        $self->{dtfile}->{created_by}->{$attr_name}->{$massoc->{id}}=1;

        # Then (re)create one DATA_CRITERIA section per extension
        foreach my $ext (@$extensions)
        {
            my $pattern="*.$ext";
            $pattern =~ s/([a-z])/[$1\U$1\E]/g;
            my $crit={DATA_ATTRIBUTES_NAME => $attr_name,
                      MODE                 => "f",
                      NAME_PATTERN         => $pattern
                     };
            $self->{dtfile}->{criteria}->{"$attr_name/$ext"}=$crit;
        }

        $self->{created}->{$mimetype}=1;
        $self->{modified}=1;
    }

    return 1;
}

sub query_mime($$$$$)
{
    my ($self, $domain, $massoc, $mimetype, $extensions)=@_;
    return 0 if (!$self->read_dt_file());

    # Check the DATA_ATTRIBUTES section matches
    my $attr_name=mangle_string($mimetype);
    my $attr=$self->{dtfile}->{attributes}->{$attr_name};
    if (!$attr)
    {
        cxlog("no $attr_name attributes section\n");
        return 0;
    }
    if ($mimetype ne ($attr->{MIME_TYPE} || ""))
    {
        cxlog("wrong mime type\n");
        return 0;
    }

    # And check that we have a valid DATA_CRITERIA section for each extension
    foreach my $ext (@$extensions)
    {
        my $criteria=$self->{dtfile}->{criteria}->{"$attr_name/$ext"};
        if (!$criteria)
        {
            cxlog("no $attr_name/$ext criteria\n");
            return 0;
        }
        if (defined $criteria->{CONTENT} or defined $criteria->{PATH_PATTERN})
        {
            cxlog("unexpected CONTENT or PATH_PATTERN field for $ext\n");
            return 0;
        }
        if (($criteria->{DATA_ATTRIBUTES_NAME} || "") ne $attr_name)
        {
            cxlog("wrong DATA_ATTRIBUTES_NAME for $ext\n");
            return 0;
        }
        if (($criteria->{MODE} || "") ne "f")
        {
            cxlog("wrong mode for $ext\n");
            return 0;
        }

        my $pattern=$ext;
        $pattern =~ s!([a-zA-Z])!\\[(?:\L$1\E\U$1\E|\U$1\E\L$1\E)\\]!g;
        if (($criteria->{NAME_PATTERN} || "") !~ /^\*\.$pattern$/)
        {
            cxlog("wrong pattern for $ext\n");
            return 0;
        }
    }

    return 1;
}

sub get_mime_files($$$$$)
{
    my ($self, $domain, $massoc, $mimetype, $extensions)=@_;
    return -f $self->{dtfilename} ? [$self->{dtfilename}] : [];
}

sub untag_mime($$$$)
{
    my ($self, $domain, $massoc, $mimetype)=@_;
    return 0 if (!$self->read_dt_file());

    my $attr_name=mangle_string($mimetype);
    my $created_by=$self->{dtfile}->{created_by}->{$attr_name};
    if ($created_by and $created_by->{$massoc->{id}})
    {
        delete $created_by->{$massoc->{id}};
        $self->{modified}=1;
    }
    my $attr=$self->{dtfile}->{attributes}->{$attr_name};
    return 1 if (!$attr);

    if (%{$self->{dtfile}->{created_by}->{$attr_name}})
    {
        cxlog("Untagging $attr_name\n");
        my $action_name="cxassoc-$self->{tag}/$massoc->{id}/$attr_name";
        # If the action has already been deleted, then delete_association()
        # won't update the ACTIONS list. So do it ourselves.
        my $actions=$attr->{ACTIONS} || "";
        if ($actions ne "")
        {
            my @alist=grep !/^$action_name$/, split /,+/, $actions;
            if (@alist)
            {
                $attr->{ACTIONS}=join(",", @alist);
                $self->{modified}=1 if ($attr->{ACTIONS} ne $actions);
            }
            else
            {
                delete $attr->{ACTIONS};
                $self->{modified}=1;
            }
        }
    }
    else
    {
        # No one is using this MIME type anymore
        cxlog("Deleting DATA_ATTRIBUTES $attr_name\n");
        delete $self->{dtfile}->{created_by}->{$attr_name};
        delete $self->{dtfile}->{attributes}->{$attr_name};
        foreach my $criteria_name (keys %{$self->{dtfile}->{criteria}})
        {
            if ($criteria_name =~ m!^$attr_name/!)
            {
                delete $self->{dtfile}->{criteria}->{$criteria_name};
            }
        }
        $self->{modified}=1;
    }

    return 1;
}


#####
#
# Association desktop file helper functions
#
#####

sub create_association($$$$)
{
    my ($self, $massoc, $adata, $extensions)=@_;
    return 0 if (!$self->read_dt_file());

    CXAssoc::setup_from_best_eassoc($massoc);
    CXAssoc::compute_verb_name($massoc);

    my $name;
    # Ampersands are not supported
    if ($massoc->{appid} ne "")
    {
        $name=join("", $massoc->{appname}, " (",
                   CXAssoc::remove_accelerators($massoc->{verbname}), ")");
    }
    elsif ($massoc->{verbname} ne "")
    {
        $name=CXAssoc::remove_accelerators($massoc->{verbname});
    }
    else
    {
        $name=$massoc->{appname};
    }
    $name="$name (" . $self->id() . ")" if ($ENV{CX_TAGALL});

    # Create an action for each DATA_ATTRIBUTES section, that is for each MIME
    # type
    foreach my $mimetype (keys %{$adata->{all_mimes}})
    {
        my $attr_name=mangle_string($mimetype);
        my $action_name="cxassoc-$self->{tag}/$massoc->{id}/$attr_name";
        my $old_action=$self->{dtfile}->{actions}->{$action_name};
        my $action={LABEL       => $name,,
                    ICON        => $massoc->{icon},
                    ARG_TYPE    => $attr_name,
                    TYPE        => "COMMAND",
                    EXEC_STRING => "$massoc->{command} \%Arg_1\%",
                    WINDOW_TYPE => "NO_STDIO"
                   };
        $action->{DESCRIPTION}=$massoc->{infotip} if ($massoc->{infotip} ne "");
        $self->{dtfile}->{actions}->{$action_name}=$action;

        my $attr=$self->{dtfile}->{attributes}->{$attr_name};
        my @alist=grep !/^$action_name$/, split /,+/, ($attr->{ACTIONS} || "");
        if ($massoc->{mode} eq "default")
        {
            unshift @alist, $action_name;
        }
        else
        {
            push @alist, $action_name;
        }
        $attr->{ACTIONS}=join(",", @alist);
    }
    $self->{modified}=1;
    return 1;
}

sub query_association($$$$)
{
    my ($self, $massoc, $adata, $state)=@_;
    return 0 if (!$self->read_dt_file());

    my $rc=($massoc->{mode} eq "default" ? "default" : "alternative");
    foreach my $mimetype (keys %{$adata->{all_mimes}})
    {
        my $attr_name=mangle_string($mimetype);
        my $action_name="cxassoc-$self->{tag}/$massoc->{id}/$attr_name";
        my $action=$self->{dtfile}->{actions}->{$action_name};
        if (!$action)
        {
            cxlog("no $action_name action\n");
            return $state;
        }

        my $attr=$self->{dtfile}->{attributes}->{$attr_name};
        my @alist=split /,+/, ($attr->{ACTIONS} || "");
        if (!grep /^$action_name$/, @alist)
        {
            cxlog("$action_name is missing from the ACTIONS field\n");
            return $state;
        }
        $rc="alternative" if ($alist[0] ne $action_name);
    }
    return $rc;
}

sub get_association_files($$$$)
{
    my ($self, $massoc, $adata, $state)=@_;
    return -f $self->{dtfilename} ? [$self->{dtfilename}] : [];
}

sub delete_association($$$)
{
    my ($self, $massoc)=@_;
    return 0 if (!$self->read_dt_file());

    foreach my $action_name (keys %{$self->{dtfile}->{actions}})
    {
        my $attr_name=$action_name;
        if ($attr_name =~ s!^cxassoc-$self->{tag}/$massoc->{id}/!!)
        {
            cxlog("Deleting ACTION $action_name\n");
            delete $self->{dtfile}->{actions}->{$action_name};
            my $attr=$self->{dtfile}->{attributes}->{$attr_name};
            next if (!$attr);

            my @alist=grep !/^$action_name$/, split /,+/, ($attr->{ACTIONS} || "");
            if (@alist)
            {
                $attr->{ACTIONS}=join(",", @alist);
            }
            else
            {
                delete $attr->{ACTIONS};
            }
            $self->{modified}=1;
        }
    }
    return 1;
}


#####
#
# Main
#
#####

sub detect($$$$)
{
    my ($class, $cxoptions, $cxconfig, $gui_info)=@_;
    return () if (!$gui_info->{cde_on});

    my $self={
        dtdir          => "$cxoptions->{destdir}$gui_info->{cde_preferred_dt}",
        global_dtdir   => $gui_info->{cde_global_dt},
        directmimes    => 1,
        do_assoc       => 1
    };
    bless $self, $class;
    $self->init_mime_handler($cxoptions);
    $self->{dtfilename}="$self->{dtdir}/cxassoc-$self->{tag}.dt";

    return ($self);
}

sub id($)
{
    my ($self)=@_;
    my $id="CXAssocCDE/$self->{dtdir}";
    $id =~ s%/+%/%g;
    return $id;
}

sub preinstall($$)
{
    my ($self, $massoc)=@_;
    return $self->collect_unix_extensions($massoc);
}

sub install($$)
{
    my ($self, $massoc)=@_;
    return $self->action($self, $massoc, "install");
}

sub query($$)
{
    my ($self, $massoc)=@_;

    if (!$massoc)
    {
        my $id=$self->id();
        return {default     => $id,
                alternative => $id,
                mime        => $id,
                partial     => $id};
    }
    return $self->action($self, $massoc, "query");
}

sub get_files($$)
{
    my ($self, $massoc)=@_;
    return $self->action($self, $massoc, "getfiles");
}

sub uninstall($$)
{
    my ($self, $massoc)=@_;
    return $self->action($self, $massoc, "uninstall");
}

sub removeall($$)
{
    my ($self, $pattern)=@_;

    my $dt_pattern;
    if ($pattern eq "legacy")
    {
        $dt_pattern="crossover.dt";
    }
    else
    {
        $dt_pattern=$pattern;
        $dt_pattern.=".*" if ($dt_pattern !~ s/\$$//);
        $dt_pattern="^cxassoc-$dt_pattern\\.dt\$";
    }

    # Delete the dt file(s)
    CXUtils::delete_files($self->{dtdir}, $dt_pattern);
    return 1;
}

sub finalize($)
{
    my ($self)=@_;

    if ($self->{modified})
    {
        if ($self->{dtfile}->is_empty())
        {
            my $filename=$self->{dtfile}->{filename};
            cxlog("CXAssocCDE deleting empty '$filename' file\n");
            # Delete the menu file
            if (-e $filename and !unlink $filename)
            {
                cxerr("unable to delete '$filename': $!\n");
                return 0;
            }
        }
        elsif (!$self->{dtfile}->save())
        {
            cxerr("unable to save '$self->{dtfile}->{filename}'\n");
        }
    }
    return 1;
}

return 1;
