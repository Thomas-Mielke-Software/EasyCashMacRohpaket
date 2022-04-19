# (c) Copyright 2005-2008, 2010, 2012, 2014. CodeWeavers, Inc.
package CXMimeMcap;
use warnings;
use strict;

use CXLog;
use CXUtils;
use CXAssoc;
use base "CXAssoc";

#####
#
# Package for reading and writing mime.types and mailcap files
# See RFC 1524 for the format of the Mailcap file
#
#####

{
    package CXRWBlob;
    use strict;

    use CXLog;
    use CXUtils;

    sub get($$)
    {
        my ($self, $mimetype)=@_;
        my $blob=$self->{mimetypes}->{$mimetype};
        return undef if (!$blob);
        return undef if ($blob->{state} eq "deleted");
        return $blob;
    }

    sub get_created_by($$$)
    {
        my ($self, $domain, $mimetype)=@_;
        my $blob=$self->{created_by}->{$mimetype}->{$domain};
        return undef if (!$blob);
        return undef if ($blob->{state} eq "deleted");
        return $blob;
    }

    sub is_crossover_mimetype($$)
    {
        my ($self, $mimetype)=@_;
        return 1 if ($self->{all_created_by}->{$mimetype});
        return 0;
    }

    sub modified($$)
    {
        my ($self, $blob)=@_;
        $blob->{state}="modified";
        $self->{modified}=1;
    }

    sub add($$$;$)
    {
        my ($self, $type, $mimetype, $domain)=@_;
        my $blob;
        if ($type eq "created-by")
        {
            $blob=$self->get_created_by($domain, $mimetype);
        }
        else
        {
            $blob=$self->get($mimetype);
        }
        if (!$blob)
        {
            $blob={
                type        => $type,
                mimetype    => $mimetype,
                state       => "up-to-date"
            };
            if ($type eq "created-by")
            {
                $self->{created_by}->{$mimetype}->{$domain}=$blob;
                $blob->{domain}=$domain;
                $blob->{tag}=$self->{tag};
                my $mime=$self->{mimetypes}->{$mimetype};
                if ($mime)
                {
                    # Add this comment next to the related MIME type
                    my $blobs=$self->{blobs};
                    my $i=$mime->{line};
                    while ($blobs->[$i])
                    {
                        if ($blobs->[$i] == $mime)
                        {
                            $i++;
                            last;
                        }
                        $i++;
                    }
                    splice @$blobs, $i, 0, $blob;
                    $blob->{line}=$i;
                }
                else
                {
                    $blob->{line}=scalar(@{$self->{blobs}});
                    push @{$self->{blobs}}, $blob;
                }
            }
            else
            {
                $self->{mimetypes}->{$mimetype}=$blob;
                $blob->{line}=scalar(@{$self->{blobs}});
                push @{$self->{blobs}}, $blob;
            }
            $self->{modified}=1;
        }
        elsif ($blob->{state} eq "deleted")
        {
            if ($type eq "created-by")
            {
                $self->{all_created_by}->{$mimetype}->{$blob->{domain}}->{$blob->{tag}}=$blob;
            }
            # It's up to the caller to clean up this blob
            $blob->{state}="modified";
        }
        if ($type eq "created-by" and $self->{type} eq "mailcap")
        {
            # For associations, make sure there's only one Created-By field
            # per MIME type
            foreach my $b (values %{$self->{all_created_by}->{$mimetype}->{$domain}})
            {
                $b->{state}="deleted" if ($b != $blob);
            }
            $self->{all_created_by}->{$mimetype}->{$blob->{domain}}={
                $blob->{tag} => $blob
            };
        }
        return $blob;
    }

    sub remove($$)
    {
        my ($self, $blob)=@_;
        $blob->{state}="deleted";
        $self->{modified}=1;
    }

    sub remove_created_by($$)
    {
        my ($self, $blob)=@_;
        $blob->{state}="deleted";
        $self->{modified}=1;

        my $all=$self->{all_created_by}->{$blob->{mimetype}};
        delete $all->{$blob->{domain}}->{$blob->{tag}};
        delete $all->{$blob->{domain}} if (!%{$all->{$blob->{domain}}});
        # Return true if the MIME type is still in use
        return %$all;
    }

    my %cxrwcache;

    sub new($$$$$)
    {
        my ($class, $tag, $filename, $type, $multiline_default)=@_;

        # Try to get the file from the cache first
        my $self;
        if (defined $filename)
        {
            $self=$cxrwcache{$filename};
            return $self if ($self);
        }

        $self={
            tag            => $tag,
            filename       => $filename,
            type           => $type,
            blobs          => [],    # Ordered list of the sections
            mimetypes      => {},    # For quick access to MIME type data
            created_by     => {},    # and to X-Created-By data
            all_created_by => {},
            multiline      => $multiline_default
        };
        bless $self, $class;

        if (defined $filename and -e $filename)
        {
            my $fh;
            return undef if (!open($fh, "<", $filename));

            my $count=0;
            while (my $line0=<$fh>)
            {
                chomp $line0;
                my $blob={
                    state => "up-to-date",
                    line  => $count,
                    lines => [ $line0 ]
                };
                push @{$self->{blobs}}, $blob;
                $count++;

                if ($line0 =~ /^\s*#\s*X-Created-By-([^:=-]*)-([^:=]*):([^= ]*)\s*=\s*(\S*)/)
                {
                    cxlog("x-created-by: [$line0]\n");
                    my ($domain, $tag, $mimetype, $apps)=($1, $2, $3, $4);
                    $mimetype=demangle_string($mimetype);
                    cxlog("domain=$domain tag=[$tag] mimetype=[$mimetype] apps=[$apps]\n");
                    $blob->{type}="created-by";
                    $blob->{domain}=$domain;
                    $blob->{tag}=$tag;
                    $blob->{mimetype}=$mimetype;
                    map { $blob->{apps}->{$_}=1 } split /;+/, $apps;
                    $self->{all_created_by}->{$mimetype}->{$domain}->{$tag}=$blob;
                    if ($self->{tag} and $self->{tag} eq $tag)
                    {
                        $self->{created_by}->{$mimetype}->{$domain}=$blob;
                    }
                }
                elsif ($line0 =~ /^\s*(#|$)/)
                {
                    cxlog("comment: [$line0]\n");
                    $blob->{type}="raw";
                }
                else
                {
                    cxlog("data: [$line0]\n");
                    my $line=$line0;
                    while (defined $line and $line =~ /\\$/)
                    {
                        $line=<$fh>;
                        last if (!defined $line);
                        chomp $line;
                        push @{$blob->{lines}}, $line;
                    }
                    $blob->{multiline}=(@{$blob->{lines}} != 1);

                    if ($line0 =~ /^\s*type=/)
                    {
                        $blob->{type}="mime";
                        $blob->{namedfields}=1;
                        $blob->{extlist}=[]; # in case 'exts=' is missing
                        # This is in the ~/.mime.types format
                        foreach my $l (@{$blob->{lines}})
                        {
                            # copy $l to not modify $blob->{lines}
                            $line = $l;
                            $line =~ s/\s*\\$//;
                            while ($line ne "")
                            {
                                my ($name, $value);
                                if ($line =~ s/^\s*([-a-zA-Z0-9_]+)\s*=\s*\"((?:[^\\\"]*|\\.)*)\"//)
                                {
                                    $name=$1;
                                    $value=unescape_string($2);
                                }
                                elsif ($line =~ s/^\s*([-a-zA-Z0-9_]+)\s*=\s*([^ =]+[^=]*[^ =]?)(?:\s+|$)//)
                                {
                                    $name=$1;
                                    $value=$2;
                                }
                                else
                                {
                                    cxlog("unable to parse '$line'\n");
                                    last;
                                }
                                $blob->{fields}->{$name}=$value;
                                if ($name eq "type")
                                {
                                    $blob->{mimetype}=$value;
                                    $self->{mimetypes}->{$value}=$blob;
                                }
                                elsif ($name eq "exts")
                                {
                                    my @extensions=split /,+/, $value;
                                    $blob->{extlist}=\@extensions;
                                }
                                elsif ($name eq "x-src")
                                {
                                    # Legacy MIME types have no notion of a
                                    # domain so just assign them to the
                                    # 'mcap' domain
                                    $blob->{created_by}->{mcap}=$value;
                                }
                            }
                        }
                    }
                    elsif ($line0 =~ /^[^ ;]*;/)
                    {
                        $blob->{type}="mailcap";
                        # This is in the ~/.mailcap or /etc/mailcap format
                        my $line0="";
                        foreach my $l (@{$blob->{lines}})
                        {
                            # copy $l to not modify $blob->{lines}
                            $line=$l;
                            $line =~ s/\\$/ /;
                            $line0.=$line;
                        }
                        my @fields=split /\s*;\s*/, $line0;
                        my $mimetype=shift @fields;
                        $self->{mimetypes}->{$mimetype}=$blob;
                        # The first field is the mimetype and the second the
                        # command but has no name. The other fields all have a
                        # name but sometimes no value.
                        $blob->{mimetype}=$mimetype;
                        $blob->{fields}->{""}=shift @fields;
                        foreach my $field (@fields)
                        {
                            if ($field =~ /^([-a-zA-Z0-9_]+)\s*=\s*\"((?:[^\\\"]*|\\.)*)\"$/)
                            {
                                my ($name, $value)=($1, $2);
                                $value=unescape_string($2);
                                $blob->{fields}->{"$name="}=$value;
                            }
                            elsif ($field =~ /^([-a-zA-Z0-9_]+)\s*=\s*(\S.*\S)$/)
                            {
                                my ($name, $value)=($1, $2);
                                $blob->{fields}->{"$name="}=$value;
                            }
                            elsif ($field =~ /^([-a-zA-Z0-9_]+)$/)
                            {
                                # This is just a boolean field so no '=' for it
                                my $name=$1;
                                $blob->{fields}->{$name}=1;
                                if ($name =~ /^x-cx/)
                                {
                                    # Legacy MIME types have no notion of a
                                    # domain so just assign them to the 'mcap'
                                    # domain
                                    $blob->{created_by}->{mcap}=$name;
                                }
                            }
                            else
                            {
                                cxlog("raw field '$field'\n");
                            }
                        }
                    }
                    elsif ($line0 !~ /;/ and @{$blob->{lines}} == 1)
                    {
                        $blob->{type}="mime";
                        # This is in the /etc/mime.types format
                        if ($line0 =~ /\s*#\s*(cx[a-z]+)\s*$/)
                        {
                            # Legacy MIME types have no notion of a domain
                            # so just assign them to the 'mcap' domain
                            $blob->{created_by}->{mcap}=$1;
                        }
                        # Remove EOL comments
                        $line0 =~ s/\s*#.*$//;
                        my @fields=split /\s+/, $line0;
                        my $mimetype=shift @fields;
                        $self->{mimetypes}->{$mimetype}=$blob;
                        $blob->{mimetype}=$mimetype;
                        $blob->{extlist}=\@fields;
                    }
                    else
                    {
                        # This is an unknown line format
                        cxlog("unable to parse:\n", join("\n", @{$blob->{lines}}),
                              "\n");
                        $blob->{type}="raw";
                        next;
                    }
                }
            }
            close($fh);
        }

        $self->{modified}=0;
        return $self;
    }

    sub isempty($)
    {
        my ($self)=@_;
        my $isempty=1;
        foreach my $blob (@{$self->{blobs}})
        {
            if ($blob->{state} ne "deleted")
            {
                $isempty=0;
                last;
            }
        }
        return $isempty;
    }

    sub save($)
    {
        my ($self)=@_;
        return 1 if (!$self->{modified});

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

        # Figure out what format to use for the new lines based on the first
        # non CrossOver line we find
        foreach my $blob (values %{$self->{mimetypes}})
        {
            next if ($blob->{created_by});
            next if ($self->is_crossover_mimetype($blob->{mimetype}));

            foreach my $field ("namedfields", "multiline")
            {
                if ($blob->{$field} and !defined $self->{$field})
                {
                    $self->{$field}=1;
                }
            }
            last;
        }

        cxlog("Saving '$self->{filename}'\n");
        foreach my $blob (@{$self->{blobs}})
        {
            if ($blob->{state} eq "up-to-date")
            {
                foreach my $line (@{$blob->{lines}})
                {
                    print $fh $line, "\n";
                }
            }
            elsif ($blob->{state} eq "modified")
            {
                # We have to rebuild the blob
                if ($blob->{type} eq "created-by")
                {
                    my $mangled=mangle_string($blob->{mimetype});
                    print $fh "# X-Created-By-$blob->{domain}-$blob->{tag}:$mangled=",
                              join(";", keys %{$blob->{apps}}), "\n";
                }
                elsif ($blob->{type} eq "mime")
                {
                    $blob->{namedfields}=$self->{namedfields} if (!defined $blob->{namedfields});
                    if ($blob->{namedfields})
                    {
                        $blob->{multiline}=$self->{multiline} if (!defined $blob->{multiline});
                        my $separator=($blob->{multiline} ? "\\\n" : "");
                        print $fh "type=$blob->{mimetype}";
                        print $fh " ${separator}desc=\"", $blob->{fields}->{"desc="}, "\"" if ($blob->{fields}->{"desc="});
                        print $fh " ${separator}exts=\"", join(",", @{$blob->{extlist}}),
                                  "\"\n";
                    }
                    else
                    {
                        print $fh "$blob->{mimetype} ",
                                  join(" ", @{$blob->{extlist}}),
                                  "\n";
                    }
                }
                else
                {
                    my $cmd=$blob->{fields}->{""};
                    $blob->{multiline}=$self->{multiline} if (!defined $blob->{multiline});
                    if ($blob->{multiline})
                    {
                        print $fh "$blob->{mimetype}; $cmd";
                        if ($blob->{fields}->{"nametemplate="})
                        {
                            print $fh "; \\\n    nametemplate=",
                                      $blob->{fields}->{"nametemplate="};
                        }
                        if ($blob->{fields}->{"description="})
                        {
                            print $fh "; \\\n    description=\"",
                                      escape_string($blob->{fields}->{"description="}), "\"";
                        }
                        print $fh "; \\\n    test=test -n \"\$DISPLAY\"";
                        print $fh "\n";
                    }
                    else
                    {
                        print $fh "$blob->{mimetype}; $cmd;";
                        if ($blob->{fields}->{"nametemplate="})
                        {
                            print $fh " nametemplate=",
                                      $blob->{fields}->{"nametemplate="}, ";";
                        }
                        print $fh " test=test -n \"\$DISPLAY\"\n";
                    }
                }
            }
        }
        close($fh);

        $self->{modified}=0;
        return 1;
    }

    sub delete_or_save($)
    {
        my ($self)=@_;
        if (!$self->isempty())
        {
            return $self->save();
        }
        if (-f $self->{filename})
        {
            cxlog("Deleting '$self->{filename}'\n");
            if (!unlink $self->{filename})
            {
                cxerr("unable to delete '$self->{filename}': $!\n");
                return 0;
            }
        }
        return 1;
    }
}


#####
#
# MIME database helper functions
#
#####

sub read_rwmime($)
{
    my ($self)=@_;
    if (!$self->{rwmime})
    {
        cxlog("Reading '$self->{mime}'\n");
        $self->{rwmime}=CXRWBlob->new($self->{tag}, $self->{mime}, "mime", 0);
    }
}

sub process_mime_file($$)
{
    my ($self, $rwfile)=@_;

    foreach my $blob (values %{$rwfile->{mimetypes}})
    {
        next if ($blob->{created_by});
        next if ($rwfile->is_crossover_mimetype($blob->{mimetype}));
        # For each MIME type, the extension list defined in /etc/mime.types
        # is merged with the one defined in ~/.mime.types, so do the same here.
        $self->mdb_add_mime($blob->{mimetype}, $blob->{extlist});
    }
}

# In this function we want to get a list of the *native Mailcap* MIME types
# and their associated extensions into the MIME database. We don't want to
# include any MIME type created by CrossOver in this list. The actual filtering
# is done by process_mime_file().
sub read_mime_db($)
{
    my ($self)=@_;
    return if ($self->{read_mime_db});
    $self->{read_mime_db}=1;

    $self->read_rwmime();
    $self->process_mime_file($self->{rwmime});

    if ($self->{global_mime} ne $self->{mime})
    {
        cxlog("Reading '$self->{global_mime}'\n");
        my $gmime=CXRWBlob->new($self->{tag}, $self->{global_mime}, "mime", 0);
        $self->process_mime_file($gmime);
    }
}


#####
#
# MIME type creation and deletion
#
#####

sub create_mime($$$$$$)
{
    my ($self, $domain, $massoc, $mime, $mimetype, $extensions)=@_;
    my $rwmime=$self->{rwmime};

    my $cxmime=$rwmime->add("mime", $mimetype, $domain);
    if (!$cxmime->{created})
    {
        cxlog("Creating '$mimetype'\n");

        CXAssoc::setup_from_best_eassoc($mime);
        my $description=$mime->{description} || $mimetype;
        $description.=" (CXMimeMcap)" if ($ENV{CX_TAGALL});

        # Recreate the MIME type from scratch...
        # Note:
        # - We should probably convert the description to the system
        #   encoding. But then I have not found a single application that
        #   uses it so there's no telling what is really allowed.
        $cxmime->{fields}={ "desc=" => $description };
        $cxmime->{extlist}=$extensions;
        # FIXME: It might be possible to use the icon, to be checked
        delete $cxmime->{lines};
        delete $cxmime->{created_by};

        $cxmime->{created}=1;
        $rwmime->modified($cxmime);
    }
    else
    {
        cxlog("Tagging  '$mimetype'\n");
    }

    my $created_by=$rwmime->add("created-by", $mimetype, $domain);
    if (!exists $created_by->{apps}->{$massoc->{id}})
    {
        $created_by->{apps}->{$massoc->{id}}=1;
        $rwmime->modified($created_by);
    }

    $self->{modified_mime}=1;
    return 1;
}

sub query_mime($$$$$)
{
    my ($self, $domain, $massoc, $mimetype, $extensions)=@_;
    my $rwmime=$self->{rwmime};

    my $created_by=$rwmime->get_created_by($domain, $mimetype);
    return 0 if (!$created_by->{apps}->{$massoc->{id}});

    my $cxmime=$rwmime->get($mimetype);
    return 0 if (!$cxmime);
    if (!$cxmime->{extensions})
    {
        map { $cxmime->{extensions}->{$_}=1 } @{$cxmime->{extlist}};
    }
    foreach my $ext (@$extensions)
    {
        return 0 if (!$cxmime->{extensions}->{$ext});
    }

    return 1;
}

sub get_mime_files($$$$$)
{
    #my ($self, $domain, $massoc, $mimetype, $extensions)=@_;
    # The mime.types file is not specific to this bottle
    # and thus must not be packaged with it.
    return [];
}

sub untag_mime($$$$)
{
    my ($self, $domain, $massoc, $mimetype)=@_;
    my $rwmime=$self->{rwmime};

    my $created_by=$rwmime->get_created_by($domain, $mimetype);
    return 1 if (!$created_by);

    if ($created_by->{apps}->{$massoc->{id}})
    {
        delete $created_by->{apps}->{$massoc->{id}};
        $rwmime->modified($created_by);
    }

    if (!%{$created_by->{apps}})
    {
        if (!$rwmime->remove_created_by($created_by))
        {
            # No one is using this MIME type anymore
            my $cxmime=$rwmime->get($mimetype);
            if ($cxmime)
            {
                $rwmime->remove($cxmime);
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

my $cxmimemcap;
sub get($$$$)
{
    my ($class, $domain, $cxoptions, $gui_info)=@_;
    if (!$cxmimemcap)
    {
        $cxmimemcap={
            mime           => "$cxoptions->{destdir}$gui_info->{mailcap_preferred_mime}",
            global_mime    => $gui_info->{mailcap_global_mime},
            domains        => []
        };
        bless $cxmimemcap, $class;
        $cxmimemcap->init_mime_handler($cxoptions);
    }
    if (!grep /^$domain$/, @{$cxmimemcap->{domains}})
    {
        push @{$cxmimemcap->{domains}}, $domain;
    }
    return $cxmimemcap;
}

sub removeall($$)
{
    my ($self, $domain, $pattern)=@_;
    $self->read_rwmime();
    if ($pattern eq "legacy")
    {
        foreach my $blob (@{$self->{rwmime}->{blobs}})
        {
            if (($blob->{created_by} || "") eq "cxoffice")
            {
                cxlog("Removing '$blob->{mimetype}' from mime.types\n");
                $self->{rwmime}->remove($blob);
            }
        }
    }
    else
    {
        my $all_created_by=$self->{rwmime}->{all_created_by};
        foreach my $mimetype (keys %$all_created_by)
        {
            foreach my $created_by (values %{$all_created_by->{$mimetype}->{$domain}})
            {
                if ($created_by->{tag} =~ /^$pattern/)
                {
                    if (!$self->{rwmime}->remove_created_by($created_by))
                    {
                        # No one is using this MIME type anymore
                        my $cxmime=$self->{rwmime}->get($mimetype);
                        if ($cxmime)
                        {
                            cxlog("Deleting $mimetype\n");
                            $self->{rwmime}->remove($cxmime);
                        }
                        else
                        {
                            cxlog("Untagged $mimetype\n");
                        }
                    }
                }
            }
        }
    }
}

sub finalize($)
{
    my ($self)=@_;
    return $self->{rwmime}->delete_or_save() if (defined $self->{rwmime});
    return 0;
}

return 1;
