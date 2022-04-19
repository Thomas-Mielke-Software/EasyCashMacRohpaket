# (c) Copyright 2002-2010. CodeWeavers, Inc.
package CXUtils;
use strict;

# Define the module interface
use vars qw(@ISA @EXPORT);
use Exporter ();
@ISA    = "Exporter";
@EXPORT = qw(cxbackquote cxexec cxgettext cxmessage cxdirname cxbasename cxmkpath cxmv cxsystem cxwait demangle_string escape_string expand_string expand_cmdline mangle_string new_shell_command shquote_string unescape_string);

use CXLog;


# Portable which(1) implementation
sub cxwhich($$;$)
{
    my ($dirs, $app, $noexec)=@_;
    if ($app =~ /^\//)
    {
        return $app if ((-x $app or $noexec) and -f $app);
    }
    elsif ($app =~ /\//)
    {
        require Cwd;
        my $path=Cwd::cwd() . "/$app";
        return $path if ((-x $path or $noexec) and -f $path);
    }
    else
    {
        foreach my $dir (split /:/, $dirs)
        {
            return "$dir/$app" if ($dir ne "" and (-x "$dir/$app" or $noexec) and -f "$dir/$app");
        }
    }
    return undef;
}



#####
#
# Product information
#
#####

sub check_product_id($)
{
    my ($productid)=@_;

    if (length($productid) < 4)
    {
        return "product id '$productid' is too short";
    }
    if ($productid !~ /^\w+$/)
    {
        return "'$productid' contains forbidden characters";
    }
    return undef;
}

sub get_builtin_product_id()
{
    return "easyct";
}

my $productid;
sub get_product_id(;\$)
{
    if (!defined $productid)
    {
        my $filename="$ENV{CX_ROOT}/.productid";
        if (-e $filename)
        {
            if (open(my $fh, "<", $filename))
            {
                $productid=<$fh>;
                chomp $productid;
                close($fh);
            }
            else
            {
                cxerr("unable to open '$filename' for reading: $!\n");
                exit 1;
            }
        }
        else
        {
            $productid=get_builtin_product_id();
        }
        my $err=check_product_id($productid || "");
        if ($err)
        {
            if (@_ >= 1)
            {
                $_[0]=$err;
                return undef;
            }
            cxerr("$err\n");
            exit 1;
        }
    }
    return $productid;
}

sub get_product_name()
{
    return "EasyCash&Tax";
}

sub get_product_version()
{
    return "20.0.4.33265local";
}

sub get_std_icon($)
{
    my ($basename)=@_;
    foreach my $ext ("png", "xpm")
    {
        foreach my $size ("48x48", "32x32", "")
        {
            my $filename="$ENV{CX_ROOT}/share/icons/$size/$basename.$ext";
            return $filename if (-f $filename);
        }
    }
    # We could not find the icon but return something anyway
    return "$ENV{CX_ROOT}/share/icons/$basename.png";
}


#####
#
# String functions
#
#####

sub hash_string($)
{
    my ($str)=@_;

    use integer;
    my $hash = 0;
    foreach my $char (split //, $str)
    {
        # The pack + unpack calls are there to enforce 32-bit arithmetic,
        # even if the Perl binary is 64-bit. This ensures we get the same
        # result in both cases.
        $hash *= 33;
        $hash = unpack "l", pack "l", $hash;
        $hash += ord($char);
        $hash = unpack "l", pack "l", $hash;
        $hash += ($hash >> 5);
        $hash = unpack "l", pack "l", $hash;
    }
    # This last pack + unpack reinterprets the result as an unsigned value
    $hash = unpack "L", pack "l", $hash;
    return $hash;
}

sub base32($$)
{
    my ($value, $digits)=@_;

    my $str="";
    my $base32="0123456789abcdefghijklmnopqrstuv";
    for (my $i=0; $i < $digits; $i++)
    {
        $str=substr($base32, ($value & 0x1f), 1) . $str;
        $value=($value >> 5);
    }
    return $str;
}

sub rfc822time($)
{
    my ($time)=@_;
    my @local=localtime($time);
    my ($sec, $min, $hour, $mday, $nmon, $year, $wday)=@local;
    $year+=1900;
    my $day=("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")[$wday];
    my $mon=("Jan", "Feb", "Mar", "Apr", "May", "Jun",
             "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")[$nmon];
    require POSIX;
    my $zone=POSIX::strftime("\%z", @local);
    return sprintf("\%s, %2d \%s %4d %02d:%02d:%02d \%s",
                   $day, $mday, $mon, $year, $hour, $min, $sec, $zone);
}

sub expand_tilde($)
{
    my ($user)=@_;
    my $subst;

    if (!$user)
    {
        $subst=$ENV{HOME} || (getpwuid($>))[7];
    }
    else
    {
        $subst=(getpwnam($user))[7];
    }
    return $subst || "~$user";
}

sub expand_string($)
{
    my ($str)=@_;
    return undef if (!defined $str);
    $str =~ s+^~([^/]*)/+expand_tilde($1) . "/"+e;
    $str =~ s+:~([^/]*)/+":" . expand_tilde($1) . "/"+e;
    $str=~ s+\$\{([^}]*)\}+$ENV{$1} || ""+ge;
    return $str;
}

sub escape_string($)
{
    my ($str)=@_;
    $str =~ s%\\%\\\\%g;
    $str =~ s%\"%\\\"%g;
    return $str;
}

sub unescape_string($)
{
    my ($str)=@_;
    $str =~ s%\\\"%\"%g;
    $str =~ s%\\\\%\\%g;
    return $str;
}

# Mangles a string so that the result is:
# - shell safe: the result does not contain characters that may be interpreted
#   by the shell: $ " ' ` < > #
# - path safe: the result does not contain characters that would be a problem
#   in a file path: / \, but also spaces and accentuated characters to avoid
#   problems with different encodings across systems
# - XML safe: the result can be used as is in XML, that is the < > and &
#   characters are removed
# - list safe: the result can be put in a list which is either colon or
#   semi-colon separated
# - KDE Exec safe: the % character is encoded and no % character is introduced
#
# The mangling operation is 100% reversible. The mangling algorithm also
# strives to keep the result as readable as possible so it uses the following
# special conversions:
#   '/' -> '_'
#   '\' -> '~'
#   ' ' -> '+'
# All other troublesome characters, are encoded by converting them to
# hexadecimal and preceding them with a '^'.
sub mangle_string($)
{
    my ($str)=@_;
    $str =~ s!([\x01-\x1f\x80-\xff\$"'`<>#&:;%^_~+])!sprintf "^%02X", ord($1)!eg;
    $str =~ s!/!_!g;
    $str =~ s!\\!~!g;
    $str =~ s! !+!g;
    return $str;
}

# Decodes a mangled string.
sub demangle_string($)
{
    my ($str)=@_;
    $str =~ s!_!/!g;
    $str =~ s!~!\\!g;
    $str =~ s!\+! !g;
    $str =~ s![\^]([0-9a-fA-F]{2})!chr(oct("0x$1"))!eg;
    return $str;
}

sub cmdline2argv($)
{
    my @chars=split "",$_[0];
    my $len=@chars;

    my @argv;
    my $in_quotes=0;
    my $bcount=0;
    my $i=0;
    my $arg="";
    while ($i<$len)
    {
        my $c=$chars[$i++];
        if (($c eq " " or $c eq "\t") and !$in_quotes)
        {
            # Close the argument and copy it
            push @argv,$arg;

            # skip the remaining spaces
            while ($i<$len)
            {
                $c=$chars[$i];
                last if ($c ne " " and $c ne "\t");
                $i++;
            }

            # Start with a new argument
            $arg="";
            $bcount=0;
        }
        elsif ($c eq "\\")
        {
            # '\\'
            $arg.=$c;
            $bcount++;
        }
        elsif ($c eq "\"")
        {
            # '"'
            if (($bcount & 1)==0)
            {
                # Preceded by an even number of '\', this is half that
                # number of '\', plus a quote which we erase.
                my $bq="\\" x ($bcount/2);
                $arg=~s/\\*$/$bq/;
                $in_quotes=!$in_quotes;
            }
            else
            {
                # Preceded by an odd number of '\', this is half that
                # number of '\' followed by a '"'
                my $bq="\\" x ($bcount/2);
                $arg=~s/\\*$/$bq\"/;
            }
            $bcount=0;
        }
        else
        {
            # a regular character
            $arg.=$c;
            $bcount=0;
        }
    }
    push @argv,$arg if ($arg ne "");
    return @argv;
}

sub expand_cmdline($)
{
    my ($str)=@_;
    return undef if (!defined $str);
    return $str if ($str !~ /\$/);
    my @args;
    foreach my $arg (map { expand_string($_) } cmdline2argv($str))
    {
        if ($arg =~ /[ "]/)
        {
            push @args, "\"" . escape_string($arg) . "\"";
        }
        else
        {
            push @args, $arg;
        }
    }
    return join(' ', @args);
}

# Quotes strings so they can be used in shell commands
# Note that this implies escaping '$'s and '`'s which may not be appropriate
# in another context.
sub shquote_string($)
{
    my ($str)=@_;
    $str =~ s%\\%\\\\%g;
    $str =~ s%\$%\\\$%g;
    $str =~ s%\"%\\\"%g;
    $str =~ s%\`%\\\`%g;
    return "\"$str\"";
}

sub argv2shcmd(@)
{
    return join(' ', map { /[^a-zA-Z0-9\/.,+_-]/ ? shquote_string($_) : $_ } @_);
}


#####
#
# Glob functions
#
#####

sub glob2regexp($;$)
{
    my ($glob, $nocase)=@_;
    # Convert the shell glob to a Perl pattern
    $glob =~ s/([].+|^\$\\\(\){}[])/\\$1/g;
    $glob =~ s/\*/.*/g;
    $glob =~ s/^\.\*/[^.].*/;
    $glob =~ s/\?/./g;
    $glob = "(?i:$glob)" if ($nocase);
    return $glob;
}

sub cxglob($$;$)
{
    my ($dir, $globs, $options)=@_;
    $options ||= "";
    my $nocase;
    $nocase=1 if ($options =~ /i/);

    my $matches=[ $dir ];
    foreach my $glob (split m!/!, $globs)
    {
        next if ($glob eq "");

        my $dirs=[];
        if ($nocase or $glob =~ /[?*]/)
        {
            $glob=glob2regexp($glob, $nocase);
            foreach my $dir (@$matches)
            {
                if (opendir(my $dh, $dir))
                {
                    foreach my $dentry (readdir $dh)
                    {
                        push @$dirs, "$dir/$dentry" if ($dentry =~ /^$glob$/);
                    }
                    closedir($dh);
                }
            }
        }
        else
        {
            foreach my $dir (@$matches)
            {
                push @$dirs, "$dir/$glob" if (-l "$dir/$glob" or -e _);
            }
        }
        return () if (!@$dirs);
        $matches=$dirs;
    }
    return @$matches;
}

sub delete_files($$;$$)
{
    my ($root, $pattern, $recursive, $prune)=@_;

    my @gc=();
    my $found=0;
    my @dirs=("");
    while (@dirs)
    {
        my $dir=shift @dirs;
        if (opendir(my $dh, "$root/$dir"))
        {
            foreach my $dentry (readdir $dh)
            {
                next if ($dentry =~ /^\.\.?$/);
                my $path="$root/$dir$dentry";
                if ($recursive and !-l $path and -d $path)
                {
                    push @dirs, "$dir$dentry/";
                }
                elsif ($dentry =~ /$pattern/)
                {
                    # $dentry may be a dangling symbolic link, so no -f test
                    cxlog("Deleting '$path'\n");
                    $found=1;
                    if (!unlink $path)
                    {
                        cxerr("unable to delete '$path': $!\n");
                    }
                }
            }
            closedir($dh);
            push @gc, $dir if ($prune);
        }
        else
        {
            cxlog("unable to open the '$dir' directory: $!\n");
        }
    }
    if ($prune)
    {
        foreach my $dir (sort { $b cmp $a } @gc)
        {
            CXUtils::garbage_collect_subdirs($root, $dir, 0);
        }
    }
    return $found;
}

sub cxfind($$;$)
{
    my ($rootdir, $pattern, $max)=@_;

    my @matches;
    my @dirs=($rootdir);
    while (@dirs)
    {
        my $dir=shift @dirs;
        if (opendir(my $dh, $dir))
        {
            foreach my $dentry (readdir $dh)
            {
                next if ($dentry =~ /^\.\.?$/);
                if ($dentry =~ /$pattern/)
                {
                    push @matches, "$dir/$dentry";
                    if (defined $max and @matches >= $max)
                    {
                        closedir($dh);
                        return @matches;
                    }
                }
                elsif (!-l "$dir/$dentry" and -d _)
                {
                    push @dirs, "$dir/$dentry";
                }
            }
            closedir($dh);
        }
    }
    return @matches;
}


#####
#
# Miscellaneous
#
#####

sub get_wine_dir_id($)
{
    my ($dev,$ino)=(stat($_[0]))[0,1];

    my $id;
    if ($dev > 0xffffffff)
    {
        $id=sprintf("%lx%08lx-", ($dev >> 32), ($dev & 0xffffffff));
    }
    else
    {
        $id=sprintf("%lx-", $dev);
    }

    if ($ino > 0xffffffff)
    {
        $id.=sprintf("%lx%08lx", ($ino >> 32), ($ino & 0xffffffff));
    }
    else
    {
        $id.=sprintf("%lx", $ino);
    }
    return $id;
}

sub get_unique_id($)
{
    my $id;

    my $uuidgen=cxwhich($ENV{PATH}, "uuidgen");
    $uuidgen=cxwhich($ENV{PATH}, "makeuuid") if (!defined $uuidgen);
    if (defined $uuidgen)
    {
        $uuidgen=shquote_string($uuidgen);
        $id=`$uuidgen 2>/dev/null`;
        chomp $id;
    }
    if (!defined $id or $id eq "")
    {
        $id=get_wine_dir_id($_[0]) . "-" . time();
    }
    return $id;
}

# Fast dirname() implementation
sub cxdirname($)
{
    my ($path)=@_;
    return undef if (!defined $path);
    return "." if ($path !~ s!/+[^/]+/*$!!s);
    return "/" if ($path eq "");
    return $path;
}

# Fast basename() implementation
sub cxbasename($)
{
    my ($path)=@_;
    return undef if (!defined $path);
    $path =~ s!/+$!!s;
    $path =~ s!^.*/+!!s;
    return $path;
}

# Return 1 if the two paths refer to the same inode, 0 if not
sub same_inode($$)
{
    my ($path1, $path2)=@_;
    return 1 if ($path1 eq $path2);

    my ($dev1, $ino1)=(stat($path1))[0,1];
    my ($dev2, $ino2)=(stat($path2))[0,1];
    return 0 if (!defined $dev1 or !defined $dev2);
    return 1 if ($dev1 == $dev2 and $ino1 == $ino2);
    return 0;
}

sub get_symlink_target($)
{
    my ($link)=@_;
    my $target=readlink($link);
    return $target if ($target =~ m%^/%);
    my $dirname=cxdirname($link);
    return "/$target" if ($dirname eq "/");
    return "$dirname/$target";
}

sub dereference_symlink($)
{
    my ($link)=@_;
    while (-l $link)
    {
        $link=get_symlink_target($link);
        last if (!-e $link);
    }
    return $link;
}

sub cxrealpath($)
{
    my ($path)=@_;

    if ($path !~ m+^/+)
    {
        require Cwd;
        $path=Cwd::cwd() . "/$path";
    }
    my $realpath="";
    foreach my $item (split m%/+%, $path)
    {
        if ($item eq "" or $item eq ".")
        {
            next;
        }
        elsif ($item eq "..")
        {
            if ($realpath eq "")
            {
                # Nothing to do
                ;
            }
            elsif (-d $realpath)
            {
                $realpath=cxdirname($realpath);
            }
            else
            {
                $realpath="$realpath/..";
            }
        }
        else
        {
            $realpath=dereference_symlink("$realpath/$item");
        }
    }
    return $realpath || "/";
}

sub cxmkpath($;$)
{
    my ($path, $mode)=@_;
    # Prevent mkpath from killing the process if it fails!
    require File::Path;
    eval { File::Path::mkpath($path, 0, $mode) };
    return ($@ ? 0 : 1);
}

sub cxmv($$)
{
    my ($src, $dst)=@_;
    return 1 if (rename($src, $dst));

    # The source and destination paths may be on different filesystems
    # So try to do a copy.
    require File::Copy;
    return undef if (!File::Copy::copy($src, $dst));
    # Return 0 in case the caller does not care about deleting the source file
    # It's still 'false' anyway
    return 0 if (!unlink $src);
    return 1;
}

sub file_grep($$)
{
    my ($filename, $regexp)=@_;

    my $fh;
    if (!open($fh, "<", $filename))
    {
        cxlog("unable to open '$filename' for reading: $!\n");
        return 0;
    }
    while (my $line=<$fh>)
    {
        if ($line =~ /$regexp/)
        {
            close($fh);
            return 1;
        }
    }
    close($fh);
    return 0;
}

my @cpio_o;
sub get_cpio_o()
{
    if (!@cpio_o)
    {
        # Mac OS X does not support the odc format
        cxbackquote("cpio -o -H odc </dev/null >/dev/null 2>&1");
        if ($?)
        {
            @cpio_o=("cpio", "-o");
        }
        else
        {
            @cpio_o=("cpio", "-o", "-H", "odc");
        }
    }
    return @cpio_o;
}

sub get_tar()
{
    return cxwhich("$ENV{PATH}:/usr/sfw/bin:/opt/csw/bin", "gtar") || "tar";
}

sub get_gzip()
{
    return cxwhich($ENV{PATH}, "pigz") || cxwhich($ENV{PATH}, "gzip");
}

sub get_bzip2()
{
    return cxwhich($ENV{PATH}, "pbzip2") || cxwhich($ENV{PATH}, "bzip2");
}

sub generate_from_template($$$)
{
    my ($dst, $template, $substitutions)=@_;

    my $in;
    if (!open($in, "<", $template))
    {
        cxerr("unable to open '$template' for reading: $!\n");
        return 1;
    }

    my $out;
    if (!open($out, ">", $dst))
    {
        cxerr("unable to open '$dst' for writing: $!\n");
        close($in);
        return 1;
    }

    while (my $line=<$in>)
    {
        if ($line =~ /\@/)
        {
            while (my ($key, $value)=each %{$substitutions})
            {
                cxerr("no value for '$key'\n") if (!defined $value);
                $line =~ s/\@$key\@/$value/g;
            }
            cxwarn("leftover template variable in:\n$line") if ($line =~ /\@[a-z_]+\@/);
        }
        print $out $line;
    }
    close($in);
    close($out);
    my $mode=(stat($template))[2] & 07777;
    chmod($mode, $dst);
    return 0;
}

sub garbage_collect_subdirs($$$)
{
    my ($root, $subdir, $delete_root)=@_;
    $subdir="/$subdir" if ($subdir !~ s%^/+%/%);
    while (1)
    {
        if ($subdir eq "/")
        {
            if ($delete_root and rmdir $root)
            {
                cxlog("Deleted '$root'\n");
            }
            last;
        }
        last if (!rmdir "$root$subdir");
        cxlog("Deleted '$root$subdir'\n");
        $subdir=cxdirname($subdir);
    }
}

# Securely take a lock
sub cxlock($)
{
    my ($name)=@_;

    my $dir=$ENV{TMPDIR} || "/tmp";
    $dir.= "/.wine-$>";

    my @st=lstat($dir);
    if (!@st)
    {
        mkdir($dir, 0700);
        @st=lstat($dir);
        if (!@st)
        {
            $@="unable to create the '$dir' directory: $!";
            return undef;
        }
    }
    if (!-d _)
    {
        $@="'$dir' is not a directory";
        return undef;
    }
    elsif ($st[4] != $>)
    {
        $@="'$dir' is not owned by you";
        return undef;
    }
    elsif ($st[2] & 077)
    {
        $@="'$dir' must not be accessible by other users";
        return undef;
    }
    my $path="$dir/$name.lock";
    if (-e $path and (-l $path or !-f $path))
    {
        $@="'$path' is not a regular file";
        return undef;
    }
    my $lock;
    if (!open($lock, ">", $path))
    {
        $@="unable to create the lock '$path': $!";
        return undef;
    }
    cxlog("$$: Grabbing the '$path' lock\n");
    if (!flock($lock, 2))
    {
        $@="unable to lock '$path': $!";
        close($lock);
        return undef;
    }
    cxlog("$$: Got the '$path' lock\n");
    return {name => $name, path => $path, lock => $lock};
}

# Note that deleting a lock carries a very high risk of causing races outside
# the scope of this function and has essentially no benefit. So the file
# created for the lock is not deleted and no support is provided for deleting
# it.
sub cxunlock($)
{
    my ($lock)=@_;
    my $rc=1;
    if ($lock)
    {
        cxlog("$$: Releasing the '$lock->{path}' lock\n");
        $lock->{unlock_hook}($lock) if ($lock->{unlock_hook});
        if (!flock($lock->{lock}, 8))
        {
            cxwarn("unable to release the '$lock->{path}' lock: $!\n");
            $rc=0;
        }
        close($lock->{lock});
    }
    return $rc;
}

sub cxexec(@)
{
    cxlog("Exec-ing '", join("' '", @_), "'\n");
    cxlog("-> failed: $!\n") if (!exec @_);
}

sub cxsystem(@)
{
    cxlog("Running '",join("' '",@_),"'\n");
    my $start=CXLog::cxtime();
    my $rc=system(@_);
    cxlog("-> rc=$rc  (took ", CXLog::cxtime()-$start, " seconds)\n");
    return $rc;
}

sub cxbackquote($;$)
{
    my ($cmd, $nolog)=@_;
    cxlog("Running `$cmd`\n");
    my $start=CXLog::cxtime();
    my @output=`$cmd`;
    cxlog("-> rc=$?  (took ", CXLog::cxtime()-$start, " seconds)\n");
    cxlog("output=[@output]\n") if ($? or !$nolog);
    return wantarray ? @output : join("", @output);
}

{
    package CXShellCommand;

    sub dump_chunk($);
    sub dump_chunk($)
    {
        my ($chunk)=@_;
        return "<undef>" if (!defined $chunk);
        return "\"$chunk\"" if (!ref($chunk));
        return "[" . join(", ", map { dump_chunk($_) } @$chunk) . "]";
    }

    sub compute_logfile($)
    {
        my ($cmd)=@_;
        if (!defined $cmd->{logfile})
        {
            $cmd->{tmpdir}||=$ENV{TMPDIR} || "/tmp";
            $cmd->{logfile}="$cmd->{tmpdir}/shlog.$$";
            $cmd->{qlogfile}=CXUtils::shquote_string($cmd->{logfile});
        }
    }

    # Build the command line, making sure we detect errors in commands before
    # pipes. Also makes it easy to prevent chatty commands like cpio and 7za
    # from polluting our output, while still reporting errors.
    sub build_cmdline($$);
    sub build_cmdline($$)
    {
        my ($cmd, $chunk)=@_;

        if (!ref(@$chunk[0]))
        {
            return (join(" ", map { $_ =~ /^[a-zA-Z0-9.\/_-]+$/ ? $_ : CXUtils::shquote_string($_) } @$chunk), "simple");
        }
        if (@$chunk[1] =~ /^(?:\|\||&&|;)$/)
        {
            my $cmdline="";
            my $i=0;
            while (1)
            {
                my ($chunkcmd, $type)=build_cmdline($cmd, @$chunk[$i]);
                if (($type eq "|" and $i != @$chunk-1) or
                    ($type eq ";" and $i != 0))
                {
                    $chunkcmd="( $chunkcmd )";
                }
                $cmdline.=$chunkcmd;
                $i++;
                last if (!defined @$chunk[$i]);
                if (@$chunk[$i] !~ /^(?:\|\||&&|;)$/)
                {
                    require Carp;
                    Carp::confess("inhomogeneous command @$chunk[$i] in ", dump_chunk($chunk), "\n");
                }
                $cmdline.=" @$chunk[$i] ";
                $i++;
            }
            return ($cmdline, ";");
        }
        if (@$chunk[1] eq "|")
        {
            my $cmdline="";
            my $i=0;
            while (1)
            {
                my ($chunkcmd, $type)=build_cmdline($cmd, @$chunk[$i]);
                $chunkcmd="( $chunkcmd )" if ($type eq ";");
                if ($i < @$chunk-1)
                {
                    $cmd->{pipe}++;
                    $cmdline.="( $chunkcmd || echo \"commands left of pipe $cmd->{pipe} failed: \$?\" ";
                    if ($cmd->{capture_output})
                    {
                        $cmdline.=">&2 ) | ";
                    }
                    else
                    {
                        compute_logfile($cmd);
                        $cmdline.=">>$cmd->{qlogfile} ) | ";
                    }
                }
                else
                {
                    $cmdline.=$chunkcmd;
                }
                $i++;
                last if (!defined @$chunk[$i]);
                if (@$chunk[$i] ne "|")
                {
                    require Carp;
                    Carp::confess("inhomogeneous command @$chunk[$i] in ", dump_chunk($chunk), "\n");
                }
                $i++;
            }
            return ($cmdline, "|");
        }
        if (@$chunk[1] =~ /^2?(?:<|>|>>)$/)
        {
            my ($chunkcmd, $type)=build_cmdline($cmd, @$chunk[0]);
            $chunkcmd="( $chunkcmd )" if ($type ne "simple");
            my $i=1;
            while (defined @$chunk[$i])
            {
                my $redirect=@$chunk[$i];
                if ($redirect !~ /^2?(?:<|>|>>)$/)
                {
                    require Carp;
                    Carp::confess("inhomogeneous command $redirect in ", dump_chunk($chunk), "\n");
                }
                $i++;
                if (defined @$chunk[$i])
                {
                    $chunkcmd.=" $redirect" . CXUtils::shquote_string(@$chunk[$i]);
                }
                elsif ($redirect =~ /^2?>$/)
                {
                    # This is to prevent chatty commands from polluting our
                    # output. So we append their output to our log (hence the
                    # extra '>') and that way we can report it in case of an
                    # error.
                    if (!$cmd->{capture_output})
                    {
                        compute_logfile($cmd);
                        $chunkcmd.=" $redirect>$cmd->{qlogfile}";
                    }
                    elsif ($redirect eq ">")
                    {
                        $chunkcmd.=" $redirect&2";
                    }
                }
                else
                {
                    require Carp;
                    Carp::confess("no file specified for $redirect in ", dump_chunk($chunk), "\n");
                }
                $i++;
            }
            return ($chunkcmd, ">");
        }

        require Carp;
        Carp::confess("unknown chunk type ", dump_chunk($chunk), "\n");
    }

    sub get_command_line($)
    {
        my ($self)=@_;
        if (!defined $self->{cmdline})
        {
            my ($cmdline, $type)=$self->build_cmdline($self->{cmd});
            if ($self->{capture_output})
            {
                $cmdline="( $cmdline )" if ($type ne "simple");
                $cmdline="$cmdline 2>&1";
            }
            $self->{cmdline}=$cmdline;
        }
        return $self->{cmdline};
    }

    sub get_output($)
    {
        my ($self)=@_;

        if (!defined $self->{output} and
            defined $self->{logfile} and -f $self->{logfile})
        {
            if (open(my $fh, "<", $self->{logfile}))
            {
                $self->{output}=<$fh>;
                close($fh);
            }
            unlink $self->{logfile};
        }
        return $self->{output};
    }

    sub has_errors($)
    {
        my ($self)=@_;
        if (!defined $self->{failed})
        {
            $self->{failed}=$self->{exit_code} || 0;
            $self->{failed}||=1 if (($self->get_output() || "") =~ /failed:/);
        }
        return $self->{failed};
    }

    sub run($)
    {
        my ($self)=@_;
        $self->get_command_line();
        if ($self->{capture_output})
        {
            $self->{output}=CXUtils::cxbackquote($self->{cmdline});
            $self->{exit_code}=$?;
        }
        else
        {
            delete $self->{output};
            $self->{exit_code}=CXUtils::cxsystem($self->{cmdline});
        }
        return $self->has_errors();
    }

    sub get_exit_code($)
    {
        my ($self)=@_;
        return $self->{exit_code};
    }

    sub get_error_report($)
    {
        my ($self)=@_;
        my $report=($self->get_output() || "") . $self->{cmdline};
        $report.=" returned $self->{exit_code}" if (defined $self->{exit_code});
        return "$report\n";
    }
}

sub new_shell_command($)
{
    my ($self)=@_;
    return undef if (!defined $self->{cmd});
    bless $self, "CXShellCommand";
    return $self;
}


#####
#
# Desktop integration
#
#####

sub cxmessage(@)
{
    return cxsystem("$ENV{CX_ROOT}/bin/cxmessage",@_);
}

sub cxwait($$@)
{
    my $pid;
    if (defined $ENV{DISPLAY} and -x "$ENV{CX_ROOT}/bin/cxwait")
    {
        $pid=fork();
        if ($pid == 0)
        {
            # Child code
            my $delay=shift @_;
            sleep($delay) if ($delay);
            # @_ must contain at least one parameter otherwise we may have
            # quoting issues. Fortunately this is guaranteed by the function
            # prototype.
            cxexec("$ENV{CX_ROOT}/bin/cxwait", @_);
            exit 1;
        }
    }
    return $pid;
}

sub cxsu(@)
{
    return cxsystem("$ENV{CX_ROOT}/bin/cxsu",@_);
}

# Detects the current desktop environment
sub get_desktop_environment()
{
    return "gnome" if (defined $ENV{GNOME_DESKTOP_SESSION_ID});
    return "mate" if (defined $ENV{MATE_DESKTOP_SESSION_ID});
    return "kde" if (defined $ENV{KDE_FULL_SESSION});
    my $cdesktop=$ENV{XDG_CURRENT_DESKTOP} || $ENV{DESKTOP_SESSION};
    if (defined $cdesktop)
    {
        return "cinnamon" if ($cdesktop =~ /cinnamon/i);
        return "deepin" if ($cdesktop =~ /deepin/i);
        return "lxqt" if ($cdesktop =~ /lxqt/i);
        return "mate" if ($cdesktop =~ /mate/i);
        return "xfce" if ($cdesktop =~ /xfce/i);
    }
    return "macosx" if (-d "/System/Library/CoreServices/Finder.app");
    # If the above failed, try using D-Bus which is slower
    foreach my $entry (["org.gnome.SessionManager", "gnome"],
                       ["org.mate.SessionManager", "mate"],
                       ["org.kde.ksmserver", "kde"])
    {
        my ($dbusid, $name)=@$entry;
        return $name if (cxsystem("dbus-send --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.GetNameOwner string:$dbusid >/dev/null 2>&1") == 0);
    }
    return "unknown";
}

# Find a terminal emulator
# Note that some terminal emulators (konsole for instance) are incapable
# of dealing with a space in the command name.
# So it is recommended to use something like this for the command:
# system(get_terminal_emulator(), "/bin/sh", "-c", $full_command_with_args)
sub get_terminal_emulator(;$)
{
    my ($title)=@_;

    my @xterm_list=("x-terminal-emulator",
                    "xterm", "lxterm",
                    "rxvt-xterm", "rxvt.bin", "rxvt",
                    "eterm", "Eterm",
                    "gnome-terminal",
                    "mate-terminal",
                    "xfce4-terminal",
                    "mlterm",
                    "konsole",
                    "deepin-terminal",
                    "dtterm",
                    "kvt",
                    "aterm",
                    "garcon-terminal-handler");
    # Try to pick the appropriate default for the current desktop environment
    my $de=get_desktop_environment();
    cxlog("desktop environment: $de\n");
    unshift @xterm_list, "mlterm" if ($de eq "cinnamon");
    unshift @xterm_list, "deepin-terminal" if ($de eq "deepin");
    unshift @xterm_list, "gnome-terminal" if ($de eq "gnome");
    unshift @xterm_list, "konsole" if ($de eq "kde");
    # Avoid lxqt's qterminal (see below)
    unshift @xterm_list, "mate-terminal" if ($de eq "mate");
    unshift @xterm_list, "xfce4-terminal" if ($de eq "xfce");

    my ($path, $has_garcon);
    foreach my $term (@xterm_list)
    {
        my $term_path=cxwhich("$ENV{PATH}:/usr/openwin/bin",$term);
        if (defined $term_path and $term eq "x-terminal-emulator")
        {
            $term_path = cxrealpath($term_path);
            if ($term_path =~ m%/garcon-terminal-handler$%)
            {
                # garcon-terminal-handler requires hooking the shell startup
                # so use it as a last resort.
                $has_garcon = 1 if (defined $ENV{HOME});
                next;
            }
            # qterminal mishandles spaces in -e arguments so avoid it
            next if ($term_path =~ m%/qterminal$%);
        }
        if (defined $term_path and -s $term_path)
        {
            $path=$term_path;
            last;
        }
    }
    if ((!$path and $has_garcon) or $path =~ m%/garcon-terminal-handler$%)
    {
        # This case requires using a wrapper
        my $cxgarcon = "$ENV{CX_ROOT}/bin/cxgarcon-terminal";
        $path = $cxgarcon if (-f $cxgarcon and -x _);
    }
    return () if (!$path);
    my @cmd=($path);
    if (!defined $title)
    {
        # Nothing to do
    }
    elsif ($path =~ m%/(?:eterm|mate-terminal|xfce4-terminal)$%i)
    {
        # Eterm, xfce4-terminal and mlterm support -T and --title
        # mate-terminal supports -t and --title
        push @cmd, "--title", $title;
    }
    elsif ($path =~ m%/(?:deepin-terminal|gnome-terminal|x-terminal-emulator)$%)
    {
        # deepin-terminal does not support any -title option.
        # gnome-terminal used to support -t, --title or even -T for some but
        # does not any longer
        # No assumption should be made for x-terminal-emulator.
    }
    else
    {
        # All other options support -title:
        # - rxvt and xterm support -T and -title
        # - aterm, dtterm and qterminal support -title
        # - konsole supports -title (-T was dropped)
        push @cmd, "-title", $title;
    }
    if ($path =~ m%/(?:gnome|mate)-terminal$%)
    {
        push @cmd, "--hide-menubar", "--";
    }
    elsif ($path =~ m%/xfce4-terminal$%)
    {
        push @cmd, "--hide-menubar", "-x";
    }
    else
    {
        push @cmd, "-e";
    }
    return @cmd;
}


#####
#
# Character set conversion
#
#####

my $system_encoding;
sub get_system_encoding(;$)
{
    my ($raw)=@_;
    if (!defined $system_encoding)
    {
        $system_encoding = "UTF-8";
        if ($@ or !$system_encoding)
        {
            $system_encoding=cxbackquote("locale charmap 2>/dev/null");
            if ($? == 0)
            {
                chomp $system_encoding;
            }
            else
            {
                $system_encoding=undef;
            }
        }
        $system_encoding="ANSI_X3.4-1968" if (!$system_encoding);
        cxlog("system encoding='$system_encoding'\n");
    }
    my $encoding=$system_encoding;
    if (!$raw and $encoding =~ /^(?:ANSI_X3\.4-1968|646)$/)
    {
        cxlog("overriding '$encoding' system encoding\n");
        $encoding="ISO-8859-1";
    }
    return $encoding;
}


#####
#
# Localization
#
#####

my $cxlocales;
sub get_supported_locales()
{
    if (!defined $cxlocales and opendir(my $dh, "$ENV{CX_ROOT}/share/locale"))
    {
        foreach my $dentry (readdir $dh)
        {
            push @$cxlocales, $dentry if ($dentry =~ /^[a-z]{2}/);
        }
        closedir($dh);
    }
    return @$cxlocales;
}

my $cxlang="";
sub cxgetlang()
{
    return $cxlang;
}

sub cxsetlang($)
{
    my $oldlang=$cxlang;
    $cxlang=$_[0] || "";
    return $oldlang;
}
my $cxencoding="";
sub cxgetencoding()
{
    return $cxencoding;
}

sub cxsetencoding($)
{
    my $oldencoding=$cxencoding;
    $cxencoding=$_[0] || "";
    return $oldencoding;
}

my %cxgettext_cache;
my $_non_c_locale;
sub cxgettext(@)
{
    my $format=shift @_;
    my $key="$cxlang:$cxencoding:$format";
    my $local_format=$cxgettext_cache{$key};
    if (!defined $local_format)
    {
        if ($format eq "")
        {
            $cxgettext_cache{$key}="";
        }
        else
        {
            my $cmd="";
            if ($cxlang)
            {
                if (!defined $_non_c_locale)
                {
                    $_non_c_locale=cxbackquote("locale -a | egrep -a -v '^(C|POSIX)\$' 2>/dev/null | head -n 1");
                    chomp $_non_c_locale;
                }
                $cmd.="LC_ALL=$_non_c_locale LANGUAGE=$cxlang ";
            }
            $cmd.=shquote_string("$ENV{CX_ROOT}/bin/cxgettext") .
                " --textdomain crossover --textdomaindir " .
                shquote_string("$ENV{CX_ROOT}/share/locale") . " ";
            $cxencoding=get_system_encoding() if (!$cxencoding);
            $cmd.="--encoding $cxencoding " . shquote_string($format);
            $cmd.=" 2>/dev/null" if (!CXLog::is_on());
            $local_format=cxbackquote($cmd);
            $local_format=$format if ($? != 0 or $local_format eq "");
            $cxgettext_cache{$key}=$local_format;
        }
    }
    return sprintf($local_format,@_);
}

sub license_file_present()
{
    my $localprefsfile;
    my $globalprefsfile;
    my $preffile_name = "de.easyct.easyct.license";

    $localprefsfile = "$ENV{HOME}/Library/Preferences/$preffile_name";
    $globalprefsfile = "/Library/Preferences/$preffile_name";

    return ( (-f $localprefsfile) || (-f $globalprefsfile) );
}

return 1;
