#!/bin/sh
# (c) Copyright 2001-2012. CodeWeavers, Inc.

kde_on=0
kde_version=""
kde_user_menu=""
kde_user_alt_menu=""
kde_user_mime=""
kde_global_menu=""
kde_global_alt_menu=""
kde_global_mime=""
kde_preferred_menu=""
kde_preferred_alt_menu=""
kde_preferred_mime=""
kde_mime_path=""

xdg_menu_on=0
xdg_user_data=""
xdg_global_data=""
xdg_preferred_data=""
xdg_data_dirs=""

xdg_mime_on=0

dtop_on=0
dtop_user_desktop=""
dtop_user_alt_desktop=""
dtop_global_desktop=""
dtop_global_alt_desktop=""
dtop_preferred_desktop=""
dtop_preferred_alt_desktop=""

debian_menu_on=0
debian_user_menu=""
debian_global_menu=""
debian_old_global_menu=""
debian_preferred_menu=""
debian_old_preferred_menu=""

debian_mime_on=0
debian_global_assoc=""
debian_preferred_assoc=""

cde_on=0
cde_user_dt=""
cde_user_wm=""
cde_global_dt=""
cde_global_wm=""
cde_preferred_dt=""
cde_preferred_wm=""

macosx_on=0

mailcap_on=0
mailcap_user_mailcap=""
mailcap_user_mime=""
mailcap_global_mailcap=""
mailcap_global_mime=""
mailcap_preferred_mailcap=""
mailcap_preferred_mime=""

desktop_assoc_ignore_list=""
desktop_menu_ignore_list=""

# Directories where to look for KDE.
kde_global_dirs="/usr /opt/kde4 /opt/kde3 /opt/kde2 /opt/kde /usr/kde/4 /usr/kde/3 /usr/kde"
kde_user_dirs="$HOME/.kde $HOME/.kde4 $HOME/.kde3 $HOME/.kde2"


# ----- Options ------

# Portable which(1) implementation
cxwhich()
{
    case "$1" in
    /*)
        if [ -x "$1" -a -f "$1" ]
        then
            echo "$1"
            return 0
        fi
        ;;
    */*)
        if [ -x "`pwd`/$1" -a -f "`pwd`/$1" ]
        then
            echo "`pwd`/$1"
            return 0
        fi
        ;;
    *)
        saved_ifs="$IFS"
        IFS=":"
        for d in $PATH
        do
            IFS="$saved_ifs"
            if [ -n "$d" -a -x "$d/$1" -a -f "$d/$1" ]
            then
                echo "$d/$1"
                return 0
            fi
        done
        ;;
    esac
    return 1
}


error()
{
    name0=`basename "$0"`
    echo "$name0:error: " "$@" >&2
}

usage=""
quiet=0
scope="private"
menu=0
assoc=0

while [ $# -gt 0 ]
do
    case "$1" in
    --quiet)
        quiet=1
        shift
        ;;
    --scope)
        scope="$2"
        shift 2
        ;;
    --menu)
        menu=1
        shift
        ;;
    --assoc)
        assoc=1
        shift
        ;;
    --help|-h|-\?)
        usage=0
        shift
        ;;
    *)
        error "unknown option '$1'"
        usage=2
        shift
        ;;
    esac
done

if [ $menu -eq 0 -a $assoc -eq 0 ]
then
    menu=1
    assoc=1
fi

if [ "$scope" != "managed" -a "$scope" != "private" ]
then
    error "unknown scope '$scope'"
    usage=2
fi

# Check that we can use $HOME and if not, unset it so buggy applications,
# like Ubuntu's kde-config, don't try to write to it
if [ -n "$HOME" ]
then
    if [ ! -d "$HOME" -o ! -w "$HOME" ]
    then
        unset HOME
    elif perl -e 'exit(($> == 0 and !-o $ARGV[0]) ? 0 : 1)' "$HOME"
    then
        # Probably an 'su' that did not update $HOME
        unset HOME
    fi
fi

if [ "$scope" != "managed" -a -z "$HOME" ]
then
    error "\$HOME must be set correctly and be writable for --scope private"
    usage=2
fi

if [ -n "$usage" ]
then
    name0=`basename "$0"`
    if [ $usage -ne 0 ]
    then
        error "try '$name0 --help' for more information"
        exit $usage
    fi
    cat <<EOF
Usage: $name0 [--quiet] [--scope SCOPE] [--menu|--assoc]

Scans for menu and association systems and returns their locations.

Options:
  --quiet       Don't print the shell commands that set all the variables
  --scope SCOPE If set to 'managed' return the system wide locations as the
                preferred location, otherwise return the per-user location
  --menu        Only scan for menuing systems
  --assoc       Only scan for association systems
EOF
    exit 0
fi


# ----- KDE ------

safe_kde_config()
{
    decoy=""
    if [ -z "$HOME" ]
    then
        decoy="/tmp/decoy.$$"
        HOME="$decoy"
        touch "$decoy"
    fi
    "$KDE_CONFIG" "$@"
    rc=$?
    [ -z "$decoy" ] || rm "$decoy"
    return $rc
}

# kde-config is not in $PATH when installing an RPM package on SuSE
# And it is not in root's $PATH on Solaris
PATH="$PATH:/opt/kde3/bin:/opt/sfw/kde/bin"

KDE_CONFIG=""
cxwhich kde4-config >/dev/null && KDE_CONFIG="kde4-config"
cxwhich kde-config >/dev/null && KDE_CONFIG="kde-config"

# First try to use kde-config.
if [ -n "$KDE_CONFIG" ]
then
    kde_apps=`safe_kde_config --path apps 2>/dev/null`
    rc=$?
    kde_user_prefix=`safe_kde_config --localprefix 2>/dev/null`
    rc=`expr $rc + $?`
    kde_global_prefix=`safe_kde_config --prefix 2>/dev/null`
    rc=`expr $rc + $?`
    kde_user_config=`safe_kde_config --path config 2>/dev/null`
    rc=`expr $rc + $?`
    if [ $assoc -ne 0 ]
    then
        kde_mime_path=`safe_kde_config --path mime 2>/dev/null`
        rc=`expr $rc + $?`
        kde_mime_path=`echo "$kde_mime_path" | sed -e 's%/:%:%g' -e 's%/$%%'`
    fi

    if [ $rc -eq 0 -a -n "$kde_user_prefix" -a -n "$kde_global_prefix" ]
    then
        kde_on=1

        # Many kde-config commands return multiple paths so we have to pick
        # the right one (user/global).
        kde_user_config=`echo "$kde_user_config" | tr ':' '\n' | egrep "^$kde_user_prefix" | head -n 1`
        if [ -z "$kde_user_config" ]
        then
            # kde-config --localprefix is broken on Gentoo so that we don't
            # find any match. Use $HOME instead.
            kde_user_prefix="$HOME/.kde"
            kde_user_config=`echo "$kde_user_config" | tr ':' '\n' | egrep "^$kde_user_prefix" | head -n 1`
        fi

        # We need these for the KDE MIME types too
        kde_user_menu=`echo "$kde_apps" | tr ':' '\n' | egrep "^$kde_user_prefix" | sed -e '2,$ d' -e 's%/$%%'`
        kde_global_menu=`echo "$kde_apps" | tr ':' '\n' | egrep "^$kde_global_prefix" | sed -e '2,$ d' -e 's%/$%%'`

        if [ $assoc -ne 0 ]
        then
            kde_user_mime=""
            kde_local_mime=""
            kde_global_mime=""
            kde_other_mime=""
            original_ifs="$IFS"
            IFS=":"
            for dir in $kde_mime_path
            do
                IFS="$original_ifs"
                if [ -z "$kde_user_mime" ] && echo "$dir" | egrep "^$kde_user_prefix" >/dev/null
                then
                    kde_user_mime="$dir"
                elif [ -z "$kde_local_mime" ] && echo "$dir" | egrep "^/usr/local/" >/dev/null
                then
                    kde_local_mime="$dir"
                elif [ -z "$kde_global_mime" ] && echo "$dir" | egrep "^$kde_global_prefix" >/dev/null
                then
                    kde_global_mime="$dir"
                else
                    kde_other_mime="$dir"
                fi
            done
            if [ -z "$kde_global_mime" ]
            then
                if [ -n "$kde_local_mime" ]
                then
                    kde_global_mime="$kde_local_mime"
                else
                    kde_global_mime="$kde_other_mime"
                fi
            fi
        fi
    fi
fi

# kde-config isn't installed.
if [ $kde_on = 0 ]
then
    # So, try to find the global KDE directory.
    for dir in $kde_global_dirs
    do
        if [ -d "$dir/share/mimelnk" ]
        then
            kde_global_prefix="$dir"
            kde_on=1
            break
        fi
    done

    # We found KDE global directory.
    if [ $kde_on = 1 ]
    then
        # Try to find the user KDE dir.
        for dir in $kde_user_dirs
        do
            if [ -d "$dir/share/mimelnk" ]
            then
                kde_user_prefix="$dir"
                break
            fi
        done
        # If no KDE user dir found, use $HOME/.kde as default.
        if [ -z "$kde_user_prefix" ]
        then
            kde_user_prefix="$HOME/.kde"
        fi

        # We need these for the KDE MIME types too
        kde_user_menu="$kde_user_prefix/share/applnk"
        kde_global_menu="$kde_global_prefix/share/applnk"

        if [ $assoc -ne 0 ]
        then
            kde_user_mime="$kde_user_prefix/share/mimelnk"
            kde_global_mime="$kde_global_prefix/share/mimelnk"
            kde_mime_path=""
            for dir in $kde_global_dirs $kde_user_dirs
            do
                if [ -d "$dir/share/mimelnk" ]
                then
                    if [ -n "$kde_mime_path" ]
                    then
                        kde_mime_path="$kde_mime_path:"
                    fi
                    kde_mime_path="$kde_mime_path$dir/share/mimelnk"
                fi
            done
        fi
    fi
fi
if [ $kde_on -eq 1 ]
then
    if [ -n "$KDE_CONFIG" ]
    then
        kvertool="safe_kde_config"
    else
        if cxwhich konqueror >/dev/null
        then
            kvertool="konqueror"
        fi
    fi
    if [ -n "$kvertool" ]
    then
        kde_version=`$kvertool --version | sed -e 's/^KDE[^:]*: \([0-9.]*\).*$/\1/' -e 't' -e 'd'`
        kde_shversion=`echo "$kde_version" | perl -pe 's/^([0-9]+(?:\.[0-9]+){2}).*$/$1/; s/\.([0-9]+)/sprintf "\%02d", $1/ge'`
    fi
fi
# We really need a default value for kde_shversion
[ -n "$kde_shversion" ] || kde_shversion="40004"


# ------ Debian menus ------

# We need the tweaked KDE menus for the KDE MIME types too
for dir in "/usr/share/menu" "/usr/lib/menu"
do
    if [ -d "$dir" ]
    then
        if cxwhich update-menus >/dev/null
        then
            debian_menu_on=1
            debian_user_menu="$HOME/.menu"
            debian_global_menu="$dir"
            if [ "$dir" != "/usr/lib/menu" -a -d "/usr/lib/menu" ]
            then
                debian_old_global_menu="/usr/lib/menu"
            fi

            # If Debian menus are in use, kde-config --path apps returns paths
            # used by the Debian menu system. We have to guess where the
            # "original" menu trees are.
            if [ -n "$kde_apps" ]
            then
                # Use the prefixes returned by kde-config.
                kde_user_menu="$kde_user_prefix/share/applnk"
                kde_global_menu="$kde_global_prefix/share/applnk"
            fi
        fi
        break
    fi
done


# ------ Debian mime settings -----

if [ $assoc -ne 0 -a -d "/usr/lib/mime/packages" ]
then
    if cxwhich update-mime >/dev/null
    then
        debian_mime_on=1
        debian_global_assoc=/usr/lib/mime/packages
    fi
fi


# ----- Mac OS X ------

if [ -f "/System/Library/DTDs/PropertyList.dtd" ]
then
    macosx_on=1
fi


# ----- XDG ------

if [ -z "$XDG_DATA_DIRS" ]
then
    xdg_data_dirs="/usr/share/gnome:/usr/local/share:/usr/share"
else
    xdg_data_dirs="$XDG_DATA_DIRS"
fi

# See if we can find XDG mime info
original_ifs="$IFS"
IFS=":"
for dir in $xdg_data_dirs
do
    IFS="$original_ifs"
    # In theory we should be putting our files in /usr/local/share because
    # that's where non-distribution files (even those of ISV applications) are
    # supposed to go. Putting our files in a random $XDG_DATA_DIRS folder even
    # used to interfere with caches sometimes.
    # However /usr/local/share usually does not exist initially and that causes
    # KDE to not find our icons until a restart. Also nobody else seems to do
    # that so it probably gets little testing.
    # So instead we try to use /usr/share like everybody else. Our files have
    # unique enough names that they should not collide with others.
    [ "$dir" = "/usr/share" ] && xdg_global_data="$dir"
    if [ -n "$dir" -a -d "$dir/applications" ]
    then
        [ -z "$xdg_global_data" ] && xdg_global_data="$dir"
        [ -f "$dir/mime/globs" -a -d "$dir/mime/packages" ] && xdg_mime_on=1
    fi
done
if [ -n "$xdg_global_data" ]
then
    if [ -z "$XDG_DATA_HOME" ]
    then
        xdg_user_data="$HOME/.local/share"
    else
        xdg_user_data="$XDG_DATA_HOME"
    fi
fi

# See if we can find XDG menu info
xdg_menus=":"
xdg_add_menu()
{
    global_menu="$1"

    # Check if this is a duplicate
    if echo "$xdg_menus" | egrep ":$global_menu:" >/dev/null
    then
        return
    fi
    xdg_menus="$xdg_menus$global_menu:"

    # Compute user_menu
    userdir="$XDG_CONFIG_HOME"
    [ -n "$userdir" ] || userdir="$HOME/.config"
    userdir="$userdir/menus"

    # Add the menu
    xdg_menu_on=`expr $xdg_menu_on + 1`
    eval "xdg_global_menu$xdg_menu_on=\"$global_menu\""
    if [ -n "$global_menu" ]
    then
        eval "xdg_user_menu$xdg_menu_on=\"$userdir\"/`basename \"$global_menu\"`"
    else
        eval "xdg_user_menu$xdg_menu_on="
    fi
    if [ "$scope" = "managed" ]
    then
        eval "xdg_preferred_menu$xdg_menu_on=\"$global_menu\""
    else
        eval "xdg_preferred_menu$xdg_menu_on=\"\$xdg_user_menu$xdg_menu_on\""
    fi
}

xdg_scan_menu_dir()
{
    menudir="$1"

    found_match=0
    for match in "$menudir"/*-applications.menu "$menudir"/applications-*.menu \
        "$menudir"/*-applications-merged "$menudir"/applications-*-merged
    do
        if [ -f "$match" -o -d "$match" ]
        then
            xdg_menu=`echo "$match" | sed -e 's/-merged$/.menu/'`
            xdg_add_menu "$xdg_menu"
            found_match=1
        fi
    done
    return $found_match
}

if [ -n "$xdg_global_data" -a -d "$xdg_global_data/applications" ]
then
    xdg_add_menu ""
fi

original_ifs="$IFS"
IFS=":"
for dir in $XDG_CONFIG_DIRS /usr/local/etc/xdg /etc/xdg
do
    IFS="$original_ifs"
    if [ -n "$dir" -a -d "$dir/menus" ]
    then
        xdg_scan_menu_dir "$dir/menus"

        # If it looks like an XDG menu directory, then always add
        # applications.menu, even if it does not exist, because it may be
        # needed if the user installed a custom KDE version somewhere
        if [ $? -eq 1 -o -f "$dir/menus/applications.menu" -o -d "$dir/menus/applications-merged" ]
        then
            xdg_add_menu "$dir/menus/applications.menu"
        fi
    fi
done

# On Ubuntu 8.04, KDE 4 puts its XDG menus in a strange place
xdg_scan_menu_dir "/usr/lib/kde4/etc/xdg/menus"


# ----- XDG desktop ------

# If ~/Desktop does not exist, then assume this is because the user
# wants it so and don't clutter his $HOME directory
if [ -d "$HOME/Desktop" -a $macosx_on -ne 1 ]
then
    dtop_on=1
    dtop_user_desktop="$HOME/Desktop"
fi


# ----- XDG User directories desktop ------

if [ -f "$HOME/.config/user-dirs.dirs" ]
then
    . "$HOME/.config/user-dirs.dirs"
    if [ -n "$XDG_DESKTOP_DIR" -a "$XDG_DESKTOP_DIR" != "$dtop_user_desktop" -a -d "$XDG_DESKTOP_DIR" ]
    then
        dtop_on=1
        dtop_user_alt_desktop="$XDG_DESKTOP_DIR"
    fi
fi


# ----- CDE ------

for dir in /etc/dt /usr/dt
do
    if [ -d "$dir/appconfig/types/C" ]
    then
        cde_global_dt="$dir/appconfig/types/C"
        cde_global_wm="$dir/config/C/wsmenu"
        cde_on=1
        break
    fi
done

if [ $cde_on ]
then
    cde_user_dt="$HOME/.dt/types"
    cde_user_wm="$HOME/.dt/wsmenu"
fi


# ----- Mailcap -----

if [ $assoc -ne 0 ]
then
    mailcap_on=1

    mailcap_user_mailcap="$HOME/.mailcap"
    mailcap_user_mime="$HOME/.mime.types"

    # Note: RFC 1524 mentions the MAILCAPS environment variable
    # but it is unclear that we need it right now
    if [ -f "/usr/dt/appconfig/netscape/etc/mailcap" ]
    then
        mailcap_global_mailcap="/usr/dt/appconfig/netscape/etc/mailcap"
        mailcap_global_mime="/usr/dt/appconfig/netscape/etc/mime.types"
    else
        mailcap_global_mailcap="/etc/mailcap"
        mailcap_global_mime="/etc/mime.types"
    fi
fi


# ----- Now we do distribution specific kludges^H^H^H^H^H^H^Hproprietary extensions


# Set the preferred paths depending on who ran the script (root/regular user).
if [ "$scope" = "managed" ]
then
    #xdg_preferred_menu*
    #dtop_preferred_desktop
    #dtop_preferred_alt_desktop

    # We need these for the KDE MIME types on Mandrake too
    debian_preferred_menu="$debian_global_menu"
    debian_old_preferred_menu="$debian_old_global_menu"

    # We need these for the KDE MIME types too
    kde_preferred_menu="$kde_global_menu"
    kde_preferred_alt_menu="$kde_global_alt_menu"

    # This is used by both menus and associations
    xdg_preferred_data="$xdg_global_data"

    if [ $assoc -ne 0 ]
    then
        kde_preferred_mime="$kde_global_mime"
        debian_preferred_assoc="$debian_global_assoc"
        mailcap_preferred_mailcap="$mailcap_global_mailcap"
        mailcap_preferred_mime="$mailcap_global_mime"
    fi
    cde_preferred_dt="$cde_global_dt"
    cde_preferred_wm="$cde_global_wm"
else
    if [ $menu -ne 0 ]
    then
        #xdg_preferred_menu*
        dtop_preferred_desktop="$dtop_user_desktop"
        dtop_preferred_alt_desktop="$dtop_user_alt_desktop"
    fi

    # We need these for the KDE MIME types on Mandrake too
    debian_preferred_menu="$debian_user_menu"

    # We need these for the KDE MIME types too
    kde_preferred_menu="$kde_user_menu"
    kde_preferred_alt_menu="$kde_user_alt_menu"

    # This is used by both menus and associations
    xdg_preferred_data="$xdg_user_data"

    if [ $assoc -ne 0 ]
    then
        kde_preferred_mime="$kde_user_mime"
        #debian_preferred_assoc
        mailcap_preferred_mailcap="$mailcap_user_mailcap"
        mailcap_preferred_mime="$mailcap_user_mime"
    fi
    cde_preferred_dt="$cde_user_dt"
    cde_preferred_wm="$cde_user_wm"
fi


# Blacklist the redundant / mutually incompatible menuing systems

if [ $debian_menu_on -eq 1 ]
then
    if [ "$scope" = "managed" -a -f "/etc/mandriva-release" ] && \
        egrep "release  *2006\\.0[^0-9]" "/etc/mandriva-release" >/dev/null 2>&1
    then
        # Don't create global Debian menus on Mandriva 2006.0
        # as this causes duplicate menu entries
        desktop_menu_ignore_list="$desktop_menu_ignore_list:CXMenuDebian$debian_preferred_menu"
    fi
fi

# Blacklist the redundant / mutually incompatible desktop icon systems

desktop_menu_ignore_list=`echo "$desktop_menu_ignore_list" | sed -e 's%//*%/%g'`

if [ $cde_on -eq 1 -a -x "/usr/dt/lib/dtobsolete" ]
then
    # On Solaris >= 10u5 invoking CDE pops up a deprecation warning
    desktop_menu_ignore_list="$desktop_menu_ignore_list:CXMenuCDE$cde_preferred_wm"
fi


# Blacklist the redundant / mutually incompatible association systems

if [ $debian_menu_on -eq 1 -a ! -d "/usr/share/applnk-mdk" ]
then
    # Creating Mandrake associations on other systems is redundant and
    # usually creates an ugly '.hidden' folder.
    desktop_assoc_ignore_list="$desktop_assoc_ignore_list:CXAssocMandrake$debian_preferred_menu"
fi

if [ $xdg_mime_on -eq 1 -a -n "$kde_preferred_mime" ]
then
    # A range of KDE 3.5 versions interpret the NoDisplay field as meaning
    # the association must not be shown in the 'Open with...' list. This is
    # in violation of the XDG specification. So for these we continue to
    # create the KDE associations.
    ignore="1"
    if [ "$kde_shversion" -ge 30500 ]
    then
        # Fedora and SUSE got fixed in 3.5.5
        fixed=30505
        # but Ubuntu got fixed in 3.5.6
        grep Ubuntu /etc/lsb-release >/dev/null 2>&1 && fixed=30506
        [ "$kde_shversion" -lt "$fixed" ] && ignore=""
    fi
    if [ -n "$ignore" ]
    then
        desktop_assoc_ignore_list="$desktop_assoc_ignore_list:CXAssocKDE$kde_preferred_menu"
    fi
fi

if [ -n "$debian_preferred_assoc" -a $mailcap_on -eq 1 ]
then
    # Debian associations replace the Mailcap ones
    desktop_assoc_ignore_list="$desktop_assoc_ignore_list:CXAssocMailcap$mailcap_preferred_mailcap"
fi

desktop_assoc_ignore_list=`echo "$desktop_assoc_ignore_list" | sed -e 's%//*%/%g'`


# Print the paths.
if [ $quiet -eq 0 ]
then
    echo "preferred_scope=$scope"

    echo "kde_on=$kde_on"
    echo "kde_version=$kde_version"
    echo "xdg_menu_on=$xdg_menu_on"
    echo "xdg_mime_on=$xdg_mime_on"
    echo "dtop_on=$dtop_on"
    echo "cde_on=$cde_on"
    echo "macosx_on=$macosx_on"

    if [ "$scope" != "managed" ]
    then
        echo "cde_user_dt=$cde_user_dt"
        echo "cde_user_wm=$cde_user_wm"
    fi
    echo "cde_global_dt=$cde_global_dt"
    echo "cde_global_wm=$cde_global_wm"
    echo "cde_preferred_dt=$cde_preferred_dt"
    echo "cde_preferred_wm=$cde_preferred_wm"

    # We need these for the KDE MIME types too
    if [ "$scope" != "managed" ]
    then
        echo "kde_user_menu=$kde_user_menu"
        echo "kde_user_alt_menu=$kde_user_alt_menu"
    fi
    echo "kde_global_menu=$kde_global_menu"
    echo "kde_global_alt_menu=$kde_global_alt_menu"
    echo "kde_preferred_menu=$kde_preferred_menu"
    echo "kde_preferred_alt_menu=$kde_preferred_alt_menu"

    if [ $menu -ne 0 ]
    then
        i=1
        while [ $i -le $xdg_menu_on ]
        do
            if [ "$scope" != "managed" ]
            then
                eval "echo xdg_user_menu$i=\$xdg_user_menu$i"
            fi
            eval "echo xdg_global_menu$i=\$xdg_global_menu$i"
            eval "echo xdg_preferred_menu$i=\$xdg_preferred_menu$i"
            i=`expr $i + 1`
        done
        if [ "$scope" != "managed" ]
        then
            echo "dtop_user_desktop=$dtop_user_desktop"
            echo "dtop_user_alt_desktop=$dtop_user_alt_desktop"
        fi
        echo "dtop_preferred_desktop=$dtop_preferred_desktop"
        echo "dtop_preferred_alt_desktop=$dtop_preferred_alt_desktop"
    fi

    # We need these for the KDE MIME types on Mandrake too
    echo "debian_menu_on=$debian_menu_on"
    if [ "$scope" != "managed" ]
    then
         echo "debian_user_menu=$debian_user_menu"
    fi
    echo "debian_global_menu=$debian_global_menu"
    echo "debian_old_global_menu=$debian_old_global_menu"
    echo "debian_preferred_menu=$debian_preferred_menu"
    echo "debian_old_preferred_menu=$debian_old_preferred_menu"

    # This is used for both menus and associations
    echo "xdg_global_data=$xdg_global_data"
    echo "xdg_preferred_data=$xdg_preferred_data"
    if [ "$scope" != "managed" ]
    then
        echo "xdg_user_data=$xdg_user_data"
    fi
    echo "xdg_data_dirs=$xdg_data_dirs"

    if [ $assoc -ne 0 ]
    then
        echo "kde_global_mime=$kde_global_mime"
        echo "kde_preferred_mime=$kde_preferred_mime"
        echo "kde_mime_path=$kde_mime_path"

        echo "debian_mime_on=$debian_mime_on"
        echo "debian_global_assoc=$debian_global_assoc"
        echo "debian_preferred_assoc=$debian_preferred_assoc"

        echo "mailcap_on=$mailcap_on"
        echo "mailcap_global_mailcap=$mailcap_global_mailcap"
        echo "mailcap_global_mime=$mailcap_global_mime"
        echo "mailcap_preferred_mailcap=$mailcap_preferred_mailcap"
        echo "mailcap_preferred_mime=$mailcap_preferred_mime"
        if [ "$scope" != "managed" ]
        then
            echo "kde_user_mime=$kde_user_mime"

            echo "mailcap_user_mailcap=$mailcap_user_mailcap"
            echo "mailcap_user_mime=$mailcap_user_mime"
        fi
    fi

    echo "desktop_assoc_ignore_list=$desktop_assoc_ignore_list"
    echo "desktop_menu_ignore_list=$desktop_menu_ignore_list"
fi
