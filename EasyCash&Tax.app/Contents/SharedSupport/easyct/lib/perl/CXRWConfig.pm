# (c) Copyright 2003-2010. CodeWeavers, Inc.
use warnings;
use strict;

{
    #
    # Manipulating the fields in a section
    #

    package CXRWSection;
    use CXUtils;
    use CXLog;

    sub new($$$)
    {
        my ($class, $name, $line)=@_;
        my $self={
            name => $name, # Section name
            lines => [],   # List of all lines
            fields => {}   # For quick access to Field and CommentField lines
        };
        bless $self, $class;
        return $self;
    }

    # For CXRWConfig's internal  use only
    sub _add_line($$)
    {
        my ($self, $field)=@_;
        push @{$self->{lines}}, $field;
        if (@$field[0] eq "Field")
        {
            my $key=@$field[1];
            $key =~ tr/A-Z/a-z/;
            $self->{fields}->{$key}=$field;
        }
        elsif (@$field[0] eq "CommentField")
        {
            my $key=@$field[1];
            $key =~ tr/A-Z/a-z/;
            my $previous=$self->{fields}->{$key};
            $self->{fields}->{$key}=$field if (!defined $previous);
        }
    }

    # For CXRWConfig's internal  use only
    sub _escape_string($$)
    {
        my ($self, $str)=@_;
        my $escaping=($self->{file} ? $self->{file}->{escaping} : "");
        if ($escaping)
        {
            if ($escaping eq "shell")
            {
                $str =~ s/\$/\\\$/g;
            }
            elsif ($escaping eq "xdg")
            {
                # Here we assume that the field names won't trigger escaping.
                # We further assume that string lists won't contain escaped
                # semi-colons.
                $str =~ s/\n/\\n/g;
                $str =~ s/\t/\\t/g;
                $str =~ s/\r/\\r/g;
                $str =~ s/\\/\\\\/g;
            }
            else
            {
                cxlog("unknown escaping scheme '$escaping'\n");
            }
        }
        return $str;
    }

    sub _unescape_char($)
    {
        my ($c)=@_;
        return "\\" if ($c eq "\\");
        return "\n" if ($c eq "n");
        return "\r" if ($c eq "r");
        return "\t" if ($c eq "t");
        return " "  if ($c eq "s");
        return $c;
    }

    # For CXRWConfig's internal  use only
    sub _unescape_string($$)
    {
        my ($self, $str)=@_;
        return undef if (!defined $str);
        my $escaping=($self->{file} ? $self->{file}->{escaping} : "");
        if ($escaping)
        {
            if ($escaping eq "shell")
            {
                $str =~ s/\\\$/\$/g;
            }
            elsif ($escaping eq "xdg")
            {
                $str =~ s!\\(.)!_unescape_char($1)!eg;
            }
            else
            {
                cxlog("unknown escaping scheme '$escaping'\n");
            }
        }
        return $str;
    }

    sub get_name($)
    {
        my ($self)=@_;
        return $self->{name};
    }

    sub get_field_list($)
    {
        my ($self)=@_;
        my @fields=map { @{$_}[1] } grep { @{$_}[0] eq "Field" } @{$self->{lines}};
        return \@fields;
    }

    sub is_commented_out($$)
    {
        my ($self, $key)=@_;
        $key =~ tr/A-Z/a-z/;
        my $field=$self->{fields}->{$key};
        return 1 if (defined $field and @$field[0] eq "CommentField");
        return 0;
    }

    sub get($$;$)
    {
        my ($self, $key, $default)=@_;
        $key =~ tr/A-Z/a-z/;
        my $field=$self->{fields}->{$key};
        my $value;
        $value=@$field[2] if (defined $field and @$field[0] eq "Field");
        $value=$default if (!defined $value);
        return $value;
    }

    # For CXRWConfig's internal  use only
    sub _rebuild_line($$)
    {
        my ($self, $field)=@_;
        my $name=@$field[1];
        my $value=@$field[2];
        if (@$field[3] eq "\"")
        {
            $name="\"" . escape_string($name) . "\"";
            $value="\"" . escape_string($value) . "\"";
        }
        my $comment=(@$field[0] eq "Field" ? "" : ";");
        my $equal=@$field[4];
        @$field[-1]=join("", $comment, $self->_escape_string($name),
                         $equal, $self->_escape_string($value));
    }

    sub comment_out($$)
    {
        my ($self, $name)=@_;
        my $key=$name;
        $key =~ tr/A-Z/a-z/;
        my $field=$self->{fields}->{$key};
        if (defined $field and @$field[0] eq "Field")
        {
            @$field[0]="CommentField";
            $self->_rebuild_line($field);
            $self->{file}->{modified}=1 if (defined $self->{file});
        }
    }

    sub set($$$)
    {
        my ($self, $name, $value)=@_;
        my $key=$name;
        $key =~ tr/A-Z/a-z/;
        my $field=$self->{fields}->{$key};
        if (!defined $field)
        {
            my $quote=$self->{file}->{quote} || "";
            my $equal=$quote ? " = " : "=";
            my $field=["Field", $name, $value, $quote, $equal, undef];
            $self->_rebuild_line($field);
            push @{$self->{lines}}, $field;
            $self->{fields}->{$key}=$field;
            $self->{file}->{modified}=1 if (defined $self->{file});
        }
        elsif ($value ne @$field[2] or $name ne @$field[1] or
               @$field[0] ne "Field")
        {
            @$field[0]="Field";
            @$field[1]=$name;
            @$field[2]=$value;
            $self->_rebuild_line($field);
            $self->{file}->{modified}=1 if (defined $self->{file});
        }
    }

    sub remove($$)
    {
        my ($self, $key)=@_;
        $key =~ tr/A-Z/a-z/;
        my $field=$self->{fields}->{$key};
        if (defined $field)
        {
            my $lines=$self->{lines};
            my $i=@$lines;
            while ($i > 0)
            {
                $i--;
                my $lfield=@$lines[$i];
                splice @$lines, $i, 1 if (defined $lfield->[1] and $lfield->[1] =~ /^\Q$key\E$/i);
            }
            delete $self->{fields}->{$key};
            $self->{file}->{modified}=1 if (defined $self->{file});
        }
    }

    sub remove_all($)
    {
        my ($self)=@_;
        $self->{lines}=[["Empty",undef,undef,undef,undef,""],
                        ["Section",undef,undef,undef,undef,"[$self->{name}]"]
                       ];
        $self->{fields}={};
        $self->{file}->{modified}=1 if (defined $self->{file});
    }
}

{
    package CXRWConfig;
    use CXLog;
    use CXUtils;


    #
    # Debug functions
    #

    sub dump_fields($)
    {
        my ($self)=@_;
        foreach my $name (@{$self->{section_list}})
        {
            cxlog("[$name]\n");
            my $section=$self->get_section($name);
            foreach my $key (sort { $a cmp $b } keys %{$section->{fields}})
            {
                my $comment=($section->is_commented_out($key) ? ";" : "");
                cxlog("  $comment","[$key] = [", $section->{fields}->{$key}->[2], "]\n");
            }
        }
    }

    sub dump_lines($)
    {
        my ($self)=@_;
        foreach my $name ("[begin]", @{$self->{section_list}})
        {
            my $section=$self->get_section($name);
            next if (!$section);
            foreach my $line (@{$section->{lines}})
            {
                cxlog("@$line[-1]\n");
            }
        }
    }


    #
    # Add / remove sections
    #

    sub _add_section($$)
    {
        my ($self, $name)=@_;
        my $key=$name;
        $key =~ tr/A-Z/a-z/;
        my $section=$self->{sections}->{$key};
        if (!defined $section)
        {
            $section=CXRWSection->new($name);
            $section->{file}=$self;
            $self->{sections}->{$key}=$section;
            push @{$self->{section_list}}, $name if ($name ne "[begin]");
            $self->{modified}=1;
        }
        return $section;
    }

    sub append_section($$)
    {
        my ($self, $name)=@_;
        my $section=$self->get_section($name);
        return $section if ($section);

        # Add an empty line before the new section so the file is readable.
        # Only add it if needed to prevent an accumulation of empty lines
        # after multiple section additions and removals.
        my $last=$self->{section_list}->[-1] || "[begin]";
        $section=$self->get_section($last);
        if ($section)
        {
            my $lines=$section->{lines};
            if (@$lines and $lines->[-1]->[0] ne "Empty")
            {
                push @$lines, ["Empty",undef,undef,undef,undef,""];
            }
        }
        $section=$self->_add_section($name);
        push @{$section->{lines}}, ["Section",undef,undef,undef,undef,"[$name]"];
        return $section;
    }

    sub get_section_keys($)
    {
        my ($self)=@_;
        return map { tr/A-Z/a-z/; } @{$self->{section_list}};
    }

    sub get_section_names($)
    {
        my ($self)=@_;
        return @{$self->{section_list}};
    }

    sub get_section($$)
    {
        my ($self, $key)=@_;
        $key =~ tr/A-Z/a-z/;
        return $self->{sections}->{$key};
    }

    sub rename_section($$$)
    {
        my ($self, $old, $new)=@_;
        my $key=$old;
        $key =~ tr/A-Z/a-z/;
        my $section=$self->{sections}->{$key};
        return undef if (!defined $section);

        my $section_list=$self->{section_list};
        for (my $i=0; $i <@$section_list; $i++)
        {
            if (@$section_list[$i] =~ /^\Q$old\E$/i)
            {
                splice @$section_list, $i, 1, $new;
                last;
            }
        }
        delete $self->{sections}->{$key};

        $section->{name}=$new;
        my $lines=$section->{lines};
        foreach my $field (@$lines)
        {
            if (@$field[0] eq "Section")
            {
                @$field[-1]="[$new]";
                last;
            }
        }
        $key=$new;
        $key =~ tr/A-Z/a-z/;
        $self->{sections}->{$key}=$section;

        $self->{modified}=1;
        return $section;
    }

    sub remove_section($$)
    {
        my ($self, $name)=@_;
        my $key=$name;
        $key =~ tr/A-Z/a-z/;
        my $section=$self->{sections}->{$key};
        return undef if (!defined $section);

        delete $self->{sections}->{$key};
        my $section_list=$self->{section_list};
        for (my $i=0; $i<@$section_list; $i++)
        {
            if (@$section_list[$i] =~ /^\Q$name\E$/i)
            {
                splice @$section_list, $i, 1;
                last;
            }
        }

        $self->{modified}=1;
        return $section;
    }

    sub remove_all($)
    {
        my ($self)=@_;
        $self->{sections}={};
        $self->{section_list}=[];
        $self->{modified}=1;
    }


    #
    # Shebang manipulation
    #

    sub set_shebang($$)
    {
        my ($self, $shebang)=@_;
        my $section=$self->_add_section("[begin]");
        $self->dump_lines();
        my $field=["raw", "", undef, undef, undef, "#!$shebang"];
        if (!@{$section->{lines}})
        {
            $section->{lines}=[$field];
        }
        elsif ($section->{lines}->[0]->[-1] =~ /^#!/)
        {
            $section->{lines}->[0]=$field;
        }
        else
        {
            unshift @{$section->{lines}}, $field;
        }
    }


    #
    # Field manipulation shortcuts
    #

    sub get($$$;$)
    {
        my ($self, $section, $field, $default)=@_;
        my $s=$self->get_section($section);
        my $value;
        $value=$s->get($field) if (defined $s);
        $value=$default if (!defined $value);
        return $value;
    }

    sub set($$$$)
    {
        my ($self, $section, $field, $value)=@_;
        my $s=$self->append_section($section);
        $s->set($field, $value);
    }


    #
    # Load / Save the configuration file
    #

    my %cxrwcache;

    sub new($$;$$)
    {
        my ($class, $filename, $escaping, $quote)=@_;
        $quote="\"" if (!defined $quote);

        # Try to get the file from the cache first
        my $self;
        if (defined $filename)
        {
            # Canonize the filename a bit for the cache
            $filename =~ s!/+!/!g;
            $self=$cxrwcache{$filename};
            return $self if ($self);
        }

        $self={
            filename => $filename,
            quote => $quote,       # The quoting style to use for new fields
            escaping => $escaping || "", # How to escape special characters
            section_list => [],    # Ordered list of the sections
            sections => {}         # For quick access to each section
        };
        bless $self, $class;
        $cxrwcache{$filename}=$self if (defined $filename);

        if (defined $filename and -e $filename)
        {
            my $fh;
            return undef if (!open($fh, "<", $filename));
            cxlog("CXRWConfig->new($filename)\n");

            my $section=$self->_add_section("[begin]");
            foreach my $line (<$fh>)
            {
                chomp $line;
                $self->{crlf}=1 if ($line =~ s/\r$//);

                my ($type, $name, $value, $quote, $equal);
                if ($line =~ /^\s*$/)
                {
                    $type="Empty";
                }
                elsif ($line =~ /^\[(.*)\]\s*(?:;[^\]]*)?$/)
                {
                    # New section
                    $section=$self->get_section($1);
                    next if (defined $section);
                    $section=$self->_add_section($1);
                    $type="Section";
                }
                elsif ($line =~ /^\s*(;+\s*)*\"((?:[^\\\"]|\\.)*)\"(\s*=\s*)\"((?:[^\\\"]|\\.)*)\"\s*(?:;.*)?$/)
                {
                    # This is a field in the following format:
                    #    "Name"="Value"
                    # or "Name" = "Value" ; comment
                    # or ;"Name" = "Value"
                    # where Name and Value are escaped strings which can
                    # contain backslashes and quotes.
                    $type=(defined $1 ? "CommentField" : "Field");
                    $name=unescape_string($2);
                    $quote="\"";
                    $equal=$3;
                    $value=unescape_string($4);
                }
                elsif ($line =~ /^\s*(;+\s*)*([^=;][^=]*?)(\s*=\s*)(.*?)\s*$/)
                {
                    # This is a field in the following format:
                    #    Name=Value
                    # or Name = Value ; also part of the value
                    # or ;Name = Value
                    # Note that this intentionally also matches
                    #    Name="Value"
                    # where the quotes are part of the value.
                    $type=(defined $1 ? "CommentField" : "Field");
                    $name=$2;
                    $quote="";
                    $equal=$3;
                    $value=$4;
                }
                else
                {
                    $type="Raw";
                }
                $name="" if (!defined $name);

                $section->_add_line([$type, $section->_unescape_string($name),
                                     $section->_unescape_string($value),
                                     $quote, $equal, $line]);
            }
            close($fh);
        }
        $self->{modified}=0;

        return $self;
    }

    sub uncache_file($)
    {
        my ($filename)=@_;
        delete $cxrwcache{$filename};
    }

    sub get_filename($)
    {
        my ($self)=@_;
        return $self->{filename};
    }

    sub get_filenames($)
    {
        my ($self)=@_;
        return [ $self->{filename} ];
    }

    sub set_filename($$)
    {
        my ($self, $filename)=@_;

        delete $cxrwcache{$self->{filename}} if (defined $self->{filename});
        $self->{filename}=$filename;
        $self->{modified}=1;
        $cxrwcache{$filename}=$self;
    }

    sub is_modified($)
    {
        my ($self)=@_;
        return $self->{modified};
    }

    sub write($$)
    {
        my ($self, $filename)=@_;

        my $fh;
        return 0 if (!open($fh, ">", $filename));
        cxlog("CXRWConfig->write($filename)\n");
        my $crlf=($self->{crlf} ? "\r\n" : "\n");
        foreach my $name ("[begin]", @{$self->{section_list}})
        {
            my $section=$self->get_section($name);
            next if (!$section);
            foreach my $line (@{$section->{lines}})
            {
                print $fh @$line[-1], $crlf;
            }
        }
        close($fh);

        return 1;
    }

    sub save($)
    {
        my ($self)=@_;
        if (!$self->{modified})
        {
            my $filename=$self->{filename} || "";
            cxlog("'$filename' not modified -> no need to save\n");
            return 1;
        }
        return 0 if (!$self->{filename});
        my $rc=$self->write($self->{filename});
        $self->{modified}=0 if ($rc);
        return $rc;
    }


    #
    # Merging configuration files
    #

    # FIXME: Merge the configuration merging code from CXUpgradeConfig
    # and switch cxupgrade to using CXRWConfig.
}

return 1;
