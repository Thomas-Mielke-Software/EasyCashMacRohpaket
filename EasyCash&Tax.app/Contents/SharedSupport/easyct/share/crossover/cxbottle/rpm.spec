#------------------------------------------------------------------------------
# This SPEC file controls the building of custom CrossOver Bottle
# RPM packages.
#
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
#   Options (see /usr/lib/rpm/macros for documentation)
#------------------------------------------------------------------------------

# Hardcode the compression algorithm to w9.gzdio which is the historical
# default. This way we produce backwards compatible packages on systems
# which use newer defaults (lzma in particular).
%define _binary_payload              w9.gzdio

# Hardcode the file digest algorithm to MD5 (1) which is the historical
# default. This way we produce backwards compatible packages on systems
# which use newer defaults.
%define _binary_filedigest_algorithm 1


#------------------------------------------------------------------------------
#   Prologue information
#------------------------------------------------------------------------------
Summary         : CrossOver Bottle RPM package
License         : Under license from CodeWeavers, as per license with @product_name@
Name            : @package_name@
Version         : @package_version@
Release         : @release@
Group           : Applications/Emulators

BuildArch       : noarch
BuildRoot       : @buildroot@
Url             : http://crossover.codeweavers.com
Packager        : @packager@

Requires        : @product_id@5
Autoreqprov     : No

# The prefix is pretty important; RPM uses this to figure out
# how to make a package relocatable
Prefix          : /opt


#------------------------------------------------------------------------------
#   Description
#------------------------------------------------------------------------------
%Description
@description@


#------------------------------------------------------------------------------
#   Files listing
#------------------------------------------------------------------------------
%files
%defattr(-,root,root)

@file_list@


%pre
#------------------------------------------------------------------------------
#   Pre install script
#------------------------------------------------------------------------------

# Setup logging
if [ -n "$CX_LOG" ]
then
    [ "$CX_LOG" = "-" ] || exec 2>>"$CX_LOG"
    echo >&2
    echo "***** `date`" >&2
    echo "Starting: $0 $@" >&2
    set -x
fi

if [ -z "$RPM_INSTALL_PREFIX" ]
then
    RPM_INSTALL_PREFIX=/opt
fi
CX_ROOT="$RPM_INSTALL_PREFIX/@product_id@"
CX_BOTTLE="@bottle@"
export CX_ROOT CX_BOTTLE

if [ ! -f "$CX_ROOT/bin/cxbottle" ]
then
    echo "error: could not find CrossOver in '$CX_ROOT'" >&2
    exit 1
fi
if [ ! -x "$CX_ROOT/bin/cxbottle" ]
then
    echo "error: the '$CX_ROOT/bin/cxbottle' tool is not executable!" >&2
    exit 1
fi
if [ ! -x "$CX_ROOT/bin/wineprefixcreate" -o ! -f "$CX_ROOT/bin/wineprefixcreate" ]
then
    echo "error: managed bottles are not supported in this version of CrossOver" >&2
    exit 1
fi

if [ -d "$CX_ROOT/support/$CX_BOTTLE" ]
then
    # Save the bottle's uuid
    "$CX_ROOT/bin/cxbottle" --get-uuid >"$CX_ROOT/support/$CX_BOTTLE/.uuid" 2>/dev/null
fi

exit 0


%post
#------------------------------------------------------------------------------
#   Post install script
#------------------------------------------------------------------------------

# Setup logging
if [ -n "$CX_LOG" ]
then
    [ "$CX_LOG" = "-" ] || exec 2>>"$CX_LOG"
    echo >&2
    echo "***** `date`" >&2
    echo "Starting: $0 $@" >&2
    set -x
fi

if [ -z "$RPM_INSTALL_PREFIX" ]
then
    RPM_INSTALL_PREFIX=/opt
fi
CX_ROOT="$RPM_INSTALL_PREFIX/@product_id@"
CX_BOTTLE="@bottle@"
export CX_ROOT CX_BOTTLE

uuid=""
uuid_file="$CX_ROOT/support/$CX_BOTTLE/.uuid"
if [ -f "$uuid_file" ]
then
    uuid=`cat "$uuid_file"`
    rm -f "$uuid_file"
fi

set_uuid=""
if [ -n "$uuid" ]
then
    set_uuid="--set-uuid $uuid"
fi

"$CX_ROOT/bin/cxbottle" $set_uuid --restored --removeall --install

exit 0


%preun
#------------------------------------------------------------------------------
#   Pre uninstallation script
#------------------------------------------------------------------------------

# Setup logging
if [ -n "$CX_LOG" ]
then
    [ "$CX_LOG" = "-" ] || exec 2>>"$CX_LOG"
    echo >&2
    echo "***** `date`" >&2
    echo "Starting: $0 $@" >&2
    set -x
fi

# If we're doing an upgrade, then do not uninstall ourselves
if [ "$1" != "0" ]
then
    exit 0
fi

if [ -z "$RPM_INSTALL_PREFIX" ]
then
    RPM_INSTALL_PREFIX=/opt
fi
CX_ROOT="$RPM_INSTALL_PREFIX/@product_id@"
CX_BOTTLE="@bottle@"
export CX_ROOT CX_BOTTLE

# Uninstall the bottle before cxbottle.conf gets deleted
"$CX_ROOT/bin/cxbottle" --removeall

exit 0


%postun
#------------------------------------------------------------------------------
#   Post uninstallation script
#------------------------------------------------------------------------------

# Setup logging
if [ -n "$CX_LOG" ]
then
    [ "$CX_LOG" = "-" ] || exec 2>>"$CX_LOG"
    echo >&2
    echo "***** `date`" >&2
    echo "Starting: $0 $@" >&2
    set -x
fi

# If we're doing an upgrade, then do not uninstall ourselves
if [ "$1" != "0" ]
then
    exit 0
fi

if [ -z "$RPM_INSTALL_PREFIX" ]
then
    RPM_INSTALL_PREFIX=/opt
fi
CX_ROOT="$RPM_INSTALL_PREFIX/@product_id@"
CX_BOTTLE="@bottle@"
export CX_ROOT CX_BOTTLE

# Delete any leftover file
rm -rf "$CX_ROOT/support/$CX_BOTTLE"

exit 0
