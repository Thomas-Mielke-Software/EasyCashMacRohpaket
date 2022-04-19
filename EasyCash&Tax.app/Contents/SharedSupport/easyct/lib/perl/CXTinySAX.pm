# (c) Copyright 2005-2008, 2010. CodeWeavers, Inc.
package CXTinySAX;
use warnings;
use strict;

use CXUtils;
use CXLog;
use XML::RegExp;


sub xml_decode($)
{
    my ($str)=@_;
    if ($str =~ /&/)
    {
        $str =~ s/&lt;/</g;
        $str =~ s/&gt;/>/g;
        # '&amp;' == '&#x26;' == '&' so make sure we don't do double demangling
        $str =~ s!&(amp|#(x[0-9a-fA-F]+));!$1 eq "amp" ? "&" : chr(oct("0$2"))!eg;
    }
    return $str;
}

sub mangle_cdata($)
{
    my ($str)=@_;
    $str =~ s/&/&amp;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/>/&gt;/g;
    $str =~ s!([\x01-\x1f])!sprintf "&#x%04X;", ord($1)!eg;
    return $str;
}

sub mangle_attribute($)
{
    my ($str)=@_;
    $str =~ s/&/&amp;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/>/&gt;/g;
    $str =~ s!([\x01-\x1f\'\"])!sprintf "&#x%04X;", ord($1)!eg;
    return $str;
}

sub parse_file($$)
{
    my ($handler, $filename)=@_;

    my $fh;
    return undef if (!open($fh, "<", $filename));
    cxlog("CXTinySAX::parse_file($filename)\n");

    my $file=join("", <$fh>);
    close($fh);

    $file =~ s%\s*\n\s*% %g;
    $file =~ s%<\s*($XML::RegExp::Name)\s+%<\n$1\n%g;
    $file =~ s%(</?|/?>)%\n$1\n%g;

    my $last_start_tag;
    my $element;
    my $attributes;
    my $cdata;

    my $depth=0;
    my $state="";
    foreach my $line (split "\n", $file)
    {
        next if ($line =~ /^\s*$/);
        if ($line eq "<")
        {
            $state="start_element";
            $cdata=undef;
        }
        elsif ($state eq "ignore")
        {
            # Ignore everything until the next start_element
        }
        elsif ($line eq "</")
        {
            $element=undef;
            $state="end_element";
        }
        elsif ($line =~ m%^/?>$%)
        {
            if ($state eq "attributes")
            {
                $handler->start_element($element, $attributes);
                $state="end_element" if ($line eq "/>");
            }
            if ($state eq "end_element")
            {
                $depth--;
                if (!defined $element)
                {
                    $element=$last_start_tag;
                    $element =~ s/^-?[0-9]+://;
                }
                if (defined $cdata and $last_start_tag eq "$depth:$element")
                {
                    $handler->cdata($element, $cdata);
                }
                $handler->end_element($element);
            }
            $state="cdata";
            $cdata="";
        }
        elsif ($state eq "start_element")
        {
            if ($line =~ /^\?xml\s+/)
            {
                if ($line =~ /\bencoding\s*=\s*\"((?:[^\\\"]*|\\.)*)\"/)
                {
                    my $encoding=unescape_string($1);
                    $handler->encoding($encoding);
                }
                $state="ignore";
            }
            elsif ($line =~ s/^!--\s*//)
            {
                $line=~s/\s*--$//;
                $handler->comment($line);
                $state="";
            }
            elsif ($line =~ /^[?!]/)
            {
                $state="ignore";
            }
            else
            {
                $element=xml_decode($line);
                $attributes={};
                $last_start_tag="$depth:$element";
                $depth++;
                $state="attributes";
            }
        }
        elsif ($state eq "end_element")
        {
            $element=xml_decode($line);
        }
        elsif ($state eq "attributes")
        {
            while ($line ne "")
            {
                if ($line =~ s/^\s*($XML::RegExp::Name)\s*=\s*\"([^\"]*)\"\s*// or
                   $line =~ s/^\s*($XML::RegExp::Name)\s*=\s*\'([^\']*)\'\s*//)
                {
                    my $name=xml_decode($1);
                    my $value=xml_decode(unescape_string($2));
                    $attributes->{$name}=$value;
                }
                else
                {
                    cxlog("unable to parse '$line' attribute(s)\n");
                    last;
                }
            }
        }
        elsif ($state eq "cdata")
        {
            $cdata=$line;
        }
    }
}

return 1;
