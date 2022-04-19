# (c) Copyright 2003-2005, 2008. CodeWeavers, Inc.
use strict;


#####
#
# The configuration file patcher
#
#####
{
    package CXUpgradeField;

    sub new($$$$)
    {
        my $class=$_[0];
        my $name=$_[1];
        my $entry=$_[2];
        my $line=$_[3];
        my $self={name    => $name,
                  entries => [$entry],
                  line => $line};
        bless $self, $class;
        return $self;
    }

    sub add_entry($$)
    {
        my $self=$_[0];
        my $entry=$_[1];
        push @{$self->{entries}},$entry;
    }

    sub get_entries($)
    {
        my $self=$_[0];
        return $self->{entries};
    }

    sub get_effective_entry($)
    {
        my $self=$_[0];

        foreach my $entry (@{$self->{entries}})
        {
            return $entry if (@$entry[0] == 0);
        }
        return undef;
    }

    sub get_value($)
    {
        my $self=$_[0];

        foreach my $entry (@{$self->{entries}})
        {
            return @$entry[2] if (@$entry[0] == 0);
        }
        return undef;
    }

    sub set_value($$)
    {
        my $self=$_[0];
        my $value=$_[1];
        foreach my $entry (@{$self->{entries}})
        {
            if (@$entry[0] == 0)
            {
                @$entry[2]=$value;
                return;
            }
        }
        push @{$self->{entries}},[0,undef,$value,undef];
    }
}

{
    package CXUpgradeSection;

    sub new($$$)
    {
        my $class=$_[0];
        my $name=$_[1];
        my $line=$_[2];
        my $self={name => $name,
                  line => $line,
                  fields => {}};
        bless $self, $class;
        return $self;
    }

    sub add_field($$)
    {
        my $self=$_[0];
        my $field=$_[1];
        my $key=$field->{name};
        $key =~ tr/A-Z/a-z/;
        $self->{fields}->{$key}=$field;
    }

    sub get_field($$)
    {
        my $self=$_[0];
        my $key=$_[1];
        $key =~ tr/A-Z/a-z/;
        return $self->{fields}->{$key};
    }

    sub get_fields($)
    {
        my $self=$_[0];
        return $self->{fields};
    }

    sub remove_field($$)
    {
        my $self=$_[0];
        my $key=$_[1];
        $key =~ tr/A-Z/a-z/;
        delete $self->{fields}->{$key};
    }

    sub add_entry($$$$)
    {
        my $self=$_[0];
        my $name=$_[1];
        my $entry=$_[2];
        my $line = $_[3];
        my $key=$name;
        $key =~ tr/A-Z/a-z/;

        my $field=$self->{fields}->{$key};
        if (defined $field)
        {
            $field->add_entry($entry);
        }
        else
        {
            $field=CXUpgradeField->new($name,$entry,$line);
            $self->{fields}->{$key}=$field;
        }
        return $field;
    }

    sub get_entry($$)
    {
        my $self=$_[0];
        my $key=$_[1];
        $key =~ tr/A-Z/a-z/;
        my $field=$self->{fields}->{$key};
        return $field->get_effective_entry() if (defined $field);
        return undef;
    }

    sub set_entry($$$)
    {
        my $entry=$_[1];
        my $value=$_[2];
        @$entry[2]=$value;
    }

    sub get($$;$)
    {
        my $self=$_[0];
        my $key=$_[1];
        my $default=$_[2];
        $key =~ tr/A-Z/a-z/;
        my $field=$self->{fields}->{$key};
        my $value;
        $value=$field->get_value() if (defined $field);
        $value=$default if (!defined $value);
        return $value;
    }

    sub set($$$)
    {
        my $self=$_[0];
        my $name=$_[1];
        my $value=$_[2];
        my $key=$name;
        $key =~ tr/A-Z/a-z/;
        my $field=$self->{fields}->{$key};
        if (defined $field)
        {
            $field->set_value($value);
        }
        else
        {
            $field=CXUpgradeField->new($name,[0,undef,$value,undef]);
            $self->{fields}->{$key}=$field;
        }
        return $field;
    }
}

{
    package CXUpgrade;
    use CXLog;

    #
    # Debug functions
    #

    sub build_entry_line($$$$$)
    {
        my $comment=$_[0];
        my $quote=$_[1];
        my $name=$_[2];
        my $value=$_[3];
        my $equal=$_[4];
        $quote="\"" if (!defined $quote);
        $equal="=" if (!defined $equal);
        return ($comment?";":"") . "$quote$name$quote$equal$quote$value$quote";
    }

    sub dump_fields($$)
    {
        my $self=$_[0];
        my $prefix=$_[1];
        $prefix="" if (!defined $prefix);

        my $quote=$self->{quote};
        foreach my $section (sort keys %{$self->{sections}})
        {
            my $s=$self->{sections}->{$section};
            cxlog($prefix,"[$s->{name}]\n");
            foreach my $fieldname (sort keys %{$s->get_fields()})
            {
                my $field=$s->get_field($fieldname);
                foreach my $entry (@{$field->get_entries()})
                {
                    cxlog($prefix,build_entry_line(@$entry[0],$quote,$fieldname,@$entry[2],@$entry[3]),"\n");
                }
            }
            cxlog($prefix,"\n");
        }
    }

    sub dump_lines($$)
    {
        my $self=$_[0];
        my $prefix=$_[1];

        foreach my $lines (@{$self->{lines}})
        {
            if (defined $lines)
            {
                foreach my $line (@$lines)
                {
                    cxlog($prefix,$line,"\n");
                }
            }
        }
    }

    #
    # Config creation functions
    #

    sub add_section($$;$)
    {
        my $self=$_[0];
        my $name=$_[1];
        my $line=$_[2];
        my $key=$name;
        $key =~ tr/A-Z/a-z/;
        my $section=$self->{sections}->{$key};
        if (!defined $section)
        {
            $section=CXUpgradeSection->new($name,$line);
            $self->{sections}->{$key}=$section;
        }
        return $section;
    }

    # Parse a line representing a variable assignment
    sub parse_variable($)
    {
        my $line=$_[0];

        if ($line =~ /^\s*(;+\s*)*\"((?:[^\\\"]*|\\.)*)\"(\s*=\s*)\"((?:[^\\\"]*|\\.)*)\"\s*(?:;.*)?$/)
        {
            # This is a field in the following format:
            #    "Name"="Value"
            # or "Name" = "Value" ; comment
            # or ;"Name" = "Value"
            # where Name and Value are escaped strings which can
            # contain backslashes and quotes.

            # Note: Does not unescape the Name and Value before returning them.
            return (defined $1?1:0, $2, $4, $3);
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
            return (defined $1?1:0, $2, $4, $3);
        }
        return (undef,undef,undef,undef);
    }

    sub new($$)
    {
        my $class=$_[0];
        my $filename=$_[1];

        my $self={filename => $filename};
        bless $self, $class;
        return $self if (!defined $filename);

        local *FILE;
        return undef if (!open(FILE,"$filename"));
        cxlog("CXUpgrade->new($filename)\n");

        my $current;
        for (my $l=0;my $line=<FILE>;$l++)
        {
            chomp $line;
            $self->{crlf}=1 if ($line =~ s/\r$//);

            push @{$self->{lines}},[$line];
            next if ($line =~ /^\s*$/);

            # New section?
            if ($line =~ /^\[([^\]]*)\]/)
            {
                $current=$self->add_section($1,$l);
                next;
            }

            # Section contents
            my ($comment,$name,$value,$equal)=parse_variable($line);
            next if (!defined $comment);
            if (!defined $name or !defined $value)
            {
                cxwarn("malformed data on line ",$l+1,", skipping\n");
                next;
            }
            if (defined $current)
            {
                $current->add_entry($name,[$comment,$l,$value,$equal],$l);
            }
            elsif ($comment == 0)
            {
                cxwarn("unexpected data found $filename:",$l+1,", skipping\n");
            }
        }
        close(FILE);
        return $self;
    }

    #
    # Config manipulation
    #
    # Important note:
    # Changes made with these functions will not be written back to the file.
    # Only merge() modifies what is written.
    #

    sub get_filename($)
    {
        my $self=$_[0];
        return $self->{filename};
    }

    sub get_section($$)
    {
        my $self=$_[0];
        my $key=$_[1];
        $key =~ tr/A-Z/a-z/;
        return $self->{sections}->{$key};
    }

    sub get_sections($)
    {
        my $self=$_[0];
        return keys %{$self->{sections}};
    }

    sub remove_section($$)
    {
        my $self=$_[0];
        my $key=$_[1];
        $key =~ tr/A-Z/a-z/;
        delete $self->{sections}->{$key};
    }

    sub rename_section($$$)
    {
        my $self=$_[0];
        my $section=$_[1];
        my $key=$_[2];

        $self->remove_section($section->{name});
        $section->{name}=$key;
        $key =~ tr/A-Z/a-z/;
        $self->{sections}->{$key}=$section;
    }

    sub get($$$;$)
    {
        my ($self, $section, $field, $default)=@_;
        my $s=$self->get_section($section);
        my $value;
        $value=$s->get($field) if (defined $s);
        $value=$default if (!defined $value);
        return $value;
    }

    sub write($$)
    {
        my $self=$_[0];
        my $filename=$_[1];

        if (!open(FILE,">$filename"))
        {
            cxerr("unable to write to '$filename': $!\n");
            return 0;
        }
        cxlog("CXUpgrade->write($filename)\n");
        my $crlf=($self->{crlf} ? "\r\n" : "\n");
        foreach my $lines (@{$self->{lines}})
        {
            if (defined $lines)
            {
                foreach my $line (@$lines)
                {
                    print FILE $line, $crlf;
                }
            }
        }
        close(FILE);

        return 1;
    }

    #
    # Misc
    #

    #
    # Merging
    #
    sub find_best_match($$)
    {
        my $field=$_[0];
        my $key=$_[1];
        return undef if (!defined $field);
        my $match;
        foreach my $entry (@{$field->get_entries()})
        {
            if (@$entry[0] eq @$key[0])
            {
                $match=$entry;
                last if (@$entry[0] eq 0 or (@$entry[0] eq 1 and @$entry[2] eq @$key[2]));
            }
            elsif (!defined $match)
            {
                $match=$entry;
            }
        }
        return $match;
    }

    sub merge_field($$$$$)
    {
        my $d_file=$_[0];
        my $d_section=$_[1];
        my $s_file=$_[2];
        my $s_section=$_[3];
        my $key=$_[4];

        cxlog("  $key\n");
        my $quote=$d_file->{quote};
        my $s_field=$s_section->get_field($key);
        my $d_field=$d_section->get_field($key);
        my $s_entry=$s_field->get_effective_entry();
        if (defined $s_entry)
        {
            my $d_entry=find_best_match($d_field,$s_entry);
            if (!defined $d_entry)
            {
                # Add the variable to this section
                cxlog("  -> adding to section\n");
                my $name=$s_field->{name};
                my $line=$d_file->{lines}->[$d_section->{line}];
                push @$line,build_entry_line(0,$quote,$name,@$s_entry[2],@$s_entry[3]);
            }
            elsif (@$s_entry[0] != @$d_entry[0] or @$s_entry[2] ne @$d_entry[2])
            {
                # Rewrite the line so it sets the specified value
                # (uncomments the line as a side effect)
                cxlog("  -> rewriting the line\n");
                my $name=$d_field->{name};
                my $line=$d_file->{lines}->[@$d_entry[1]];
                @$line[0]=build_entry_line(0,$quote,$name,@$s_entry[2],@$d_entry[3]);
            }
        }
        else
        {
            if (!defined $d_field)
            {
                # Add the comments to this section
                cxlog("  -> adding comments to the section\n");
                my $line=$d_file->{lines}->[$d_section->{line}];
                foreach my $s_entry (@{$s_field->get_entries()})
                {
                    push @$line,$s_file->{lines}->[@$s_entry[1]]->[0];
                }
            }
            else
            {
                my $d_placeholder;
                my $d_entry=$d_field->get_effective_entry();
                if (defined $d_entry)
                {
                    cxlog("  -> commenting out the field\n");
                    # Comment out the field
                    my $line=$d_file->{lines}->[@$d_entry[1]];
                    @$line[0]=";" . @$line[0];
                    @$d_entry[0]=1;
                }
                elsif (@{$d_field->get_entries()} eq 1)
                {
                    $d_placeholder=@{$d_field->get_entries()}[0];
                }

                # And merge the comments
                for (my $i=@{$s_field->get_entries()}-1;$i>=0;$i--)
                {
                    my $s_entry=@{$s_field->get_entries()}[$i];
                    $d_entry=find_best_match($d_field,$s_entry);
                    if (defined $d_entry and @$s_entry[2] eq @$d_entry[2])
                    {
                        # we already have the exact same line in $d_file
                        # so there is no need to change the template
                        if (defined $d_placeholder and $d_entry eq $d_placeholder)
                        {
                            $d_placeholder=undef;
                        }
                    }
                    else
                    {
                        cxlog("  -> adding comment\n");
                        # Add the source field as a comment
                        $d_entry=@{$d_field->get_entries()}[0] if (!defined $d_entry);
                        my $line=$d_file->{lines}->[@$d_entry[1]];
                        splice @$line,0,0,$s_file->{lines}->[@$s_entry[1]]->[0];
                    }
                }
                if (defined $d_placeholder and @$d_placeholder[2] eq "")
                {
                    # Remove the placeholder
                    cxlog("  -> removing the placeholder\n");
                    my $line=$d_file->{lines}->[@$d_placeholder[1]];
                    pop @$line;
                }
            }
        }
    }

    sub merge($$)
    {
        my $d_file=$_[0];
        my $s_file=$_[1];

        foreach my $s_section (sort { ($a->{line} || 0) <=> ($b->{line} || 0) } values %{$s_file->{sections}})
        {
            cxlog("[$s_section->{name}]\n");
            my $d_section=$d_file->get_section($s_section->{name});
            if (defined $d_section)
            {
                cxlog("  Merging fields...\n");
                # Update the destination variables with the values from the
                # source file
                my $fields=$s_section->get_fields();
                if (defined $fields)
                {
                    foreach my $key (sort { ($fields->{$a}->{line} || 0) <=> ($fields->{$b}->{line} || 0) } keys %$fields)
                    {
                        $d_file->merge_field($d_section,$s_file,$s_section,$key);
                    }
                }
            }
            else
            {
                # Append this section at the end of the file
                cxlog("  Appending section...\n");
                my $l=$s_section->{line};

                # Add the comments immediately preceding the section
                $l--;
                while ($l>0)
                {
                    last if ($s_file->{lines}->[$l]->[0] !~ /^\s*;/);
                    $l--;
                }
                while ($l>0)
                {
                    last if ($s_file->{lines}->[$l]->[0] !~ /^\s*$/);
                    $l--;
                }
                $l++;

                # Do not copy those immediately preceding the next section
                my $last=$s_section->{line}+1;
                while ($last<@{$s_file->{lines}})
                {
                    last if ($s_file->{lines}->[$last]->[0] =~ /^\[[^\]]/);
                    $last++;
                }
                if ($last<@{$s_file->{lines}})
                {
                    $last--;
                    while ($last>0)
                    {
                        last if ($s_file->{lines}->[$last]->[0] !~ /^\s*;/);
                        $last--;
                    }
                    while ($last>0)
                    {
                        last if ($s_file->{lines}->[$last]->[0] !~ /^\s*$/);
                        $last--;
                    }
                    $last++;
                }

                my $scount=1;
                while ($l<$last)
                {
                    my $line=$s_file->{lines}->[$l];
                    if (@$line[0] =~ /^\[[^\]]/)
                    {
                        last if ($scount == 0);
                        $scount--;
                    }
                    push @{$d_file->{lines}},$line;
                    $l++;
                }
            }
        }
    }
}

return 1;
