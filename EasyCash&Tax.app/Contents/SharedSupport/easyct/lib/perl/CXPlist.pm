# (c) Copyright 2006, 2010. CodeWeavers, Inc.
package CXPlist;
use warnings;
use strict;
use CXLog;
use CXXMLDOM;


#####
#
# Helper functions to manipulate dictionaries
#
#####

sub get_key_by_name($$)
{
    my ($dict, $name)=@_;
    $name=CXXMLDOM::utf8_to_unicode($name);
    cxlog("looking for [$name]\n");
    my $node=$dict->getFirstChild();
    while (defined $node)
    {
        if ($node->getNodeName() eq "key")
        {
            my $text=get_cdata($node);
            cxlog("  key=$text\n");
            if ($text eq $name)
            {
                cxlog("  -> found\n");
                return $node;
            }
        }
        $node=$node->getNextSibling();
    }
    cxlog("  -> not found\n");
    return undef;
}

sub get_key_by_value($)
{
    my ($node)=@_;
    while ($node)
    {
        $node=$node->getPreviousSibling();
        return $node if (ref($node) ne "XML::DOM::Text");
    }
    return undef;
}

sub get_value_by_key($)
{
    my ($node)=@_;
    while ($node)
    {
        $node=$node->getNextSibling();
        return $node if (ref($node) ne "XML::DOM::Text");
    }
    return undef;
}

sub get_value_by_name($$)
{
    my ($dict, $name)=@_;
    my $key=get_key_by_name($dict, $name);
    return undef if (!$key);
    return get_value_by_key($key);
}

sub add_key_with_string($$$)
{
    my ($dict, $keyname, $str)=@_;
    add_new_element($dict, "key", $keyname);
    add_new_element($dict, "string", $str);
    return 1;
}

sub add_key_with_child($$$)
{
    my ($dict, $keyname, $value)=@_;
    add_new_element($dict, "key", $keyname);
    add_element($dict, $value);
    return 1;
}

sub add_key_with_new_tag($$$)
{
    my ($dict, $keyname, $tag)=@_;
    add_new_element($dict, "key", $keyname);
    return add_new_element($dict, $tag);
}

return 1;
