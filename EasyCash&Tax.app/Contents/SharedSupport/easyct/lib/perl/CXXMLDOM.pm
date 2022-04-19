# (c) Copyright 2005-2008, 2010. CodeWeavers, Inc.
package CXXMLDOM;
use warnings;
use strict;
use CXLog;
use CXUtils;
use base "Exporter";
use vars '@EXPORT';
@EXPORT = qw(get_cdata
             set_cdata
             get_child
             find_tag
             find_next_tag
             get_child_by_name
             get_tag_by_path
             create_element
             add_element
             add_new_element
             set_element
             remove_element
            );


#####
#
# Loading XML::DOM / XML files
#
#####

my $xmldom_err;
BEGIN
{
    eval "no warnings 'all';use XML::Handler::BuildDOM;use XML::SAX::PurePerl;";
    $xmldom_err="$@";
}

sub get_xml_load_error()
{
    return $xmldom_err;
}

sub parse_xml_file($)
{
    my ($filename)=@_;

    my $handler = new XML::Handler::BuildDOM();
    my $parser = new XML::SAX::PurePerl(Handler => $handler);
    cxlog("Reading XML file from '$filename'\n");
    my $xml;
    my $start=CXLog::cxtime();
    eval { $xml=$parser->parse_uri($filename); };
    cxlog("parsing took ", CXLog::cxtime()-$start, " seconds\n");
    if ($@)
    {
        cxerr("unable to parse '$filename': $@\n");
        return undef;
    }
    return $xml;
}

sub parse_xml_string($)
{
    my ($str)=@_;
    my $xml;
    my $handler = new XML::Handler::BuildDOM();
    my $parser = new XML::SAX::PurePerl(Handler => $handler);
    eval { $xml=$parser->parse_string($str); };
    if ($@)
    {
        cxerr("unable to parse XML string: $@\n");
        return undef;
    }
    return $xml;
}

sub save_xml_file($$;$)
{
    my ($filename, $xml, $prefix)=@_;
    cxlog("Writing '$filename'\n");
    my $dir=cxdirname($filename);
    if (!cxmkpath($dir))
    {
        cxerr("unable to create directory '$dir/': $!\n");
        return 0;
    }
    my $fh;
    if (!open($fh, ">:encoding(UTF-8)", "$filename.tmp-$$"))
    {
        cxerr("unable to open '$filename.tmp-$$' for writing: $!\n");
        return 0;
    }
    print $fh $prefix if ($prefix);
    print $fh $xml->toString();
    close($fh);
    if (!rename("$filename.tmp-$$", $filename))
    {
        cxerr("unable to update '$filename': $!\n");
        return 0;
    }
    return 1;
}


#####
#
# UTF8 to / from Unicode
#
#####

# Notes:
# - If the utf8 module is available, then strings containing accents will have
#   been converted to Perl's internal Unicode representation by the XML parser.
#   But comparisons of a Unicode string with the same raw UTF-8 string fail
#   which will cause us to fail to find folders for instance. So we must
#   convert our strings to Unicode too.
# - The utf8 module is not available or non-functional in early Perl 5.6
#   versions. So use pack (a bit slower) as a fallback.

my $has_utf8=(defined &utf8::is_utf8);

sub is_unicode($)
{
    my ($str)=@_;
    return utf8::is_utf8($str) if ($has_utf8);

    # Plan B for when utf8::is_utf8() is not available
    require bytes;
    return 0 if (!defined $str);
    return (length($str) != bytes::length($str));
}

sub utf8_to_unicode($)
{
    my ($str)=@_;
    if ($has_utf8)
    {
        utf8::decode($str);
    }
    elsif (defined $str)
    {
        $str=pack "U0A*", $str;
    }
    return $str;
}

sub unicode_to_utf8($)
{
    my ($str)=@_;
    if ($has_utf8)
    {
        utf8::encode($str);
    }
    elsif (defined $str)
    {
        $str=pack "C0A*", $str;
    }
    return $str;
}

sub string_properties($)
{
    my ($str)=@_;
    return "Undefined" if (!defined $str);

    require bytes;
    my $clen=length($str);
    my $blen=bytes::length($str);
    my $ascii=($str =~ /^[\x01-\x7f]*$/);
    my $prop="Unicode " . ($clen != $blen ? "On" : "Off") .
             ($ascii ? ", Ascii" : ", Non-Ascii") .
             ", $clen Characters, $blen Bytes";
}


#####
#
# XML helper functions
#
#####

sub dump_dom($$);
sub dump_dom($$)
{
    my ($prefix, $node)=@_;

    my $type=ref($node);
    $type =~ s/^XML::DOM:://;
    my $name=$node->getNodeName() || "<undef>";
    my $value=$node->getNodeValue() || "<undef>";
    cxlog("$prefix<$type>\n");
    cxlog("$prefix  $name=[$value]\n");
    my $child=$node->getFirstChild();
    while (defined $child)
    {
        dump_dom("$prefix  ", $child);
        $child=$child->getNextSibling();
    }
    cxlog("$prefix</$type>\n");
}

sub get_cdata($)
{
    my ($node)=@_;
    $node=$node->getFirstChild();
    return "" if (!defined $node);
    return $node->getData() || "";
}

sub set_cdata($$)
{
    my ($node, $str)=@_;

    # Replace the text of that node
    # Remove the old children if any
    while (1)
    {
        my $n=$node->getFirstChild();
        last if (!defined $n);
        $node->removeChild($n);
    }
    my $text=XML::DOM::Text->new($node->getOwnerDocument());
    $text->setData(utf8_to_unicode($str));
    $node->appendChild($text);
    return $node;
}

sub get_child($$)
{
    my ($parent, $tag)=@_;

    my $child=$parent->getFirstChild();
    while (defined $child)
    {
        return $child if ($child->getNodeName() eq $tag);
        $child=$child->getNextSibling();
    }
    return undef;
}

sub find_tag($$)
{
    my ($root, $tag)=@_;

    my @nodes=($root);
    while (@nodes)
    {
        my $node=shift @nodes;
        my $child=$node->getFirstChild();
        while (defined $child)
        {
            return $child if ($child->getNodeName() eq $tag);
            push @nodes, $child if (ref($child) eq "XML::DOM::Element");
            $child=$child->getNextSibling();
        }
    }
    return undef;
}

sub find_next_tag($$)
{
    my ($node, $tag)=@_;

    while (defined $node)
    {
        return $node if ($node->getNodeName() eq $tag);
        $node=$node->getNextSibling();
    }
    return undef;
}

sub get_child_by_name($$$)
{
    my ($parent, $tag, $name)=@_;
    $name=utf8_to_unicode($name);

    my $child=$parent->getFirstChild();
    while (defined $child)
    {
        if ($child->getNodeName() eq $tag)
        {
            my $text=get_child($child, "Name");
            return $child if (get_cdata($text) eq $name);
        }
        $child=$child->getNextSibling();
    }
    return undef;
}

sub get_tag_by_path($$$)
{
    my ($folder, $tag, $path)=@_;

    foreach my $name (split "/", $path)
    {
        # Ignore empty names to deal with leading and trailing '/'s
        next if ($name eq "");
        $folder=get_child_by_name($folder, $tag, $name);
        return undef if (!defined $folder);
    }
    return $folder;
}


#####
#
# XML helper methods
#
#####

sub create_element($$;$)
{
    my ($owner, $name, $str)=@_;

    my $element=XML::DOM::Element->new($owner, $name);
    if (defined $str)
    {
        my $text=XML::DOM::Text->new($owner);
        $text->setData(utf8_to_unicode($str));
        $element->appendChild($text);
    }
    return $element;
}

sub add_element($$;$)
{
    my ($parent, $child, $position)=@_;

    if (!$position)
    {
        $position=$parent->getLastChild();
        $position=undef if (ref($position) ne "XML::DOM::Text");
    }
    $parent->insertBefore($child, $position);

    # Now insert some extra Text objects for indentation
    my $indent="";
    my $text=get_child($parent, "#text");
    if (ref($text) ne "XML::DOM::Text" or
        ($indent=$text->getData()) !~ /^\s+$/)
    {
        $text=$parent->getPreviousSibling();
        $indent=$text->getData() . "  " if (ref($text) eq "XML::DOM::Text");
    }
    $indent =~ s/^.*\n//;
    if ($indent =~ /^\s*$/)
    {
        my $owner=$parent->getOwnerDocument();
        my $sibling=$child->getPreviousSibling();
        if (ref($sibling) ne "XML::DOM::Text")
        {
            $text=XML::DOM::Text->new($owner);
            $text->setData("\n$indent");
            $parent->insertBefore($text, $child);
        }
        $sibling=$child->getNextSibling();
        if (ref($sibling) ne "XML::DOM::Text")
        {
            $indent=~s/  $// if (!$sibling);
            $text=XML::DOM::Text->new($owner);
            $text->setData("\n$indent");
            $parent->insertBefore($text, $sibling);
        }
    }

    return $child;
}

sub add_new_element($$;$$)
{
    my ($parent, $name, $str, $position)=@_;
    my $child=create_element($parent->getOwnerDocument(), $name, $str);
    return add_element($parent, $child, $position);
}

sub set_element($$;$$)
{
    my ($parent, $name, $str, $position)=@_;

    my $child=get_child($parent, $name);
    return set_cdata($child, $str) if (defined $child);

    $position=$position->getNextSibling() if (defined $position);
    return add_new_element($parent, $name, $str, $position);
}

sub remove_element($$)
{
    my ($parent, $node)=@_;
    my $sibling=$node->getPreviousSibling();
    if (ref($sibling) eq "XML::DOM::Text" and
        ref($node->getNextSibling()) eq "XML::DOM::Text")
    {
        # Remove redundant indentation object
        # Note that this impacts any code that tries to iterate the children
        $parent->removeChild($sibling);
    }
    $parent->removeChild($node);
}

return 1;
