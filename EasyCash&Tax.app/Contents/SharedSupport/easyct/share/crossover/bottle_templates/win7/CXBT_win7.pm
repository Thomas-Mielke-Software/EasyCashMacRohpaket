# (c) Copyright 2008, 2010-2012. CodeWeavers, Inc.
package CXBT_win7;
use strict;

use CXLog;
use CXUtils;

my $productid=CXUtils::get_product_id();
my $template="win7";
my $datadir="$ENV{CX_ROOT}/share/crossover/bottle_data";
my $templatedir="$ENV{CX_ROOT}/share/crossover/bottle_templates/$template";
my $windows_version="win7";
my $winearch="win32";


my $default_eassocids=".asf:.cfc:.disco:.doc:.dochtml:.dot:.dwr:.dwt:.efx:.em:.emp:.fla:.mdb:.moh:.mov:.mpw:.mpx:.net:.pdf:.pic:.pict:.ppt:.prj:.psd:.psf:.psp:.qdb:.qdf:.qdt:.qfx:.qt:.sch:.swf:.vrml:.vsd:.vst:.vss:.wma:.wmv:.xls";
my $alternative_eassocids=".csv:.rtf";

my $ignore_plugins="_NPDOC\\.DLL\$:_NPDocBox\\.dll\$:_npmozax\\.dll\$:_nppdf32\\.dll\$";


#
# Bottle template query
#

sub new($$)
{
    my ($class)=@_;

    my $self={ };
    bless $self, $class;
    return $self;
}

sub query($$$)
{
    my ($self, $type, $params)=@_;

    if ($type eq "introspect")
    {
        # Return a very general description of the template.
        # This query is supported by all templates.
        return { properties => { category => "crossover" } };
    }

    $@="Unknown query type '$type'";
    return undef;
}


#
# Bottle creation / upgrade helpers
#

sub create_windows_label()
{
    my $filename="$ENV{WINEPREFIX}/dosdevices/c:/.windows-label";
    if (!-f $filename and open(my $fh, ">", $filename))
    {
        print $fh "drive_c";
        close($fh);
    }
}

sub run_inf($$$;$)
{
    my ($winver, $scope, $upgrade, $unix_paths)=@_;

    my $section;
    if ($upgrade)
    {
        # Upgrades shouldn't change the bottle version
        $section="DefaultInstall";
    }
    elsif (($winver || "") =~ /^(win98|win2000|winxp|vista|win7|win8|win10)$/)
    {
        # Registry key names are case insensitive :-)
        $section="${winver}Install";
    }
    else
    {
        cxerr("unknown Windows version '$winver'\n");
    }

    my @cxoptions=();
    if (defined $winver)
    {
        # We must both use --winver, for when called from cxbottle, and set
        # CX_WINDOWS_VERSION, for when called by wine, i.e. when the Wine
        # environment is already set.
        $ENV{CX_WINDOWS_VERSION}=$winver;
        push @cxoptions, "--winver", $winver;
    }

    my $shdocvwmode="b";
    my $shdocvwpath=$unix_paths->{"c:/windows/system32/shdocvw.dll"};
    if ($shdocvwpath and open(my $shdocvwdll, "<", $shdocvwpath))
    {
        binmode $shdocvwdll;
        seek($shdocvwdll, 0x40, 0);
        my $tag;
        read($shdocvwdll, $tag, 20);
        close($shdocvwdll);
        $shdocvwmode="d" if ($tag ne "Wine placeholder DLL");
    }

    # Set up some dll overrides to register Wine's dlls
    $ENV{WINEDLLOVERRIDES}=join(";",
        "advpack=b",      # Older native advpack miss an API for builtin IE
        "atl=b",          # Older native atl break registration
        "oleaut32=b",     # Workaround for a native oleaut32 bug
        "rpcrt4=b",       # Incompatibility with native rpcrt4
        "shdocvw=$shdocvwmode", # wine.inf invokes 'iexplore -regserver' which
        "*iexplore.exe=b"       # is specific to the builtin version
    );
    # Note that this will also run wine.inf if needed
    if ($section)
    {
        if (cxsystem("$ENV{CX_ROOT}/bin/wine", "--wl-app", "rundll32.exe",
                     "--no-quotes", "--scope", $scope, @cxoptions,
                     "--desktop", "root", "--dll", $ENV{WINEDLLOVERRIDES},
                     "setupapi.dll,InstallHinfSection", $section, "128",
                     "$datadir/crossover.inf"))
        {
            $@="'rundll32 $section crossover.inf' failed\n";
            return undef;
        }

        if ($winearch eq "win64" and
            -f "$ENV{CX_ROOT}/bin/wineloader" and
            cxsystem("$ENV{CX_ROOT}/bin/wine", "--wl32-app", "rundll32.exe",
                     "--no-quotes", "--scope", $scope, @cxoptions,
                     "--desktop", "root", "--dll", $ENV{WINEDLLOVERRIDES},
                     "setupapi.dll,InstallHinfSection", $section, "128",
                     "$datadir/crossover.inf"))
        {
            $@="'rundll32 $section crossover.inf' failed\n";
            return undef;
        }
    }
    delete $ENV{CX_WINDOWS_VERSION};
    return 1;
}


#
# Bottle upgrade
#

sub rename_fake_windows()
{
    my $fake_windows="$ENV{WINEPREFIX}/fake_windows";
    if (-d $fake_windows and !-l $fake_windows)
    {
        # Rename fake_windows to drive_c, but leave a symlinked
        # fake_windows behind in order not to break existing scripts.
        my $drive_c="$ENV{WINEPREFIX}/drive_c";
        if (!rename $fake_windows, $drive_c)
        {
            $@="unable to move '$fake_windows' to '$drive_c': $!\n";
            return undef;
        }
        if (!symlink "drive_c", $fake_windows)
        {
            cxwarn("unable to create '$fake_windows' link: $!\n");
        }

        my $drive_link="$ENV{WINEPREFIX}/dosdevices/c:";
        if (-l $drive_link and readlink($drive_link) eq "../fake_windows")
        {
            unlink $drive_link;
            if (!symlink "../drive_c", $drive_link)
            {
                $@="unable to create '$drive_link' link\n";
                return undef;
            }
        }
    }
    return 1;
}

sub upgrade_cxbottle($$)
{
    my ($cxconfig, $params)=@_;

    require CXUpgrade;
    my $filename="$ENV{WINEPREFIX}/cxbottle.conf";
    cxlog("\n** Upgrading $filename\n\n");
    my $src=CXUpgrade->new($filename);
    $src=CXUpgrade->new(undef) if (!defined $src);
    my $s=$src->get_section("Bottle");
    my $old_version;
    if (defined $s)
    {
        $old_version=$s->get("Version", "2.0.0");
        $old_version=~s/[^0-9.].*$//;
    }
    else
    {
        $old_version=$params->{old_version} || "1.3.1";
    }
    $old_version=~s/^([0-9]\.)/0$1/;
    cxlog("Old Version=$old_version\n");

    my $template="$datadir/cxbottle.conf";
    my $dst=CXUpgrade->new($template);
    if (!defined $dst)
    {
        cxerr("unable to read '$template': $!\n");
        return ($old_version, $src);
    }

    # Tweak the configuration values
    my ($encoding, $bottleid);
    $s=$src->get_section("Bottle");
    if (defined $s)
    {
        # Reset the Version field
        $s->remove_field("Version");
        $s->set("Timestamp", $cxconfig->get("CrossOver", "BuildTimestamp", ""));
        $encoding=$s->get("Encoding");

        # In version < 2.0 the Updater field was called WinePrefixCreate
        # and was stored in cxoffice.conf! So for these antique versions,
        # simply assume that if this looks like a managed bottle,
        # it probably is.
        my $updater=$s->get("Updater");
        if (!defined $updater and $old_version lt "02.0" and $> == 0 and
            $ENV{WINEPREFIX} eq "$ENV{CX_ROOT}/support/dotwine")
        {
            $s->set("Updater", "wineprefixcreate");
        }

        $bottleid=$s->get("BottleID");
    }
    else
    {
        $s=$src->add_section("Bottle");
    }

    # Before these existed, bottles were always considered to be installed
    $s->set("MenuMode", "install") if (!defined $s->get("MenuMode"));
    $s->set("AssocMode", "install") if (!defined $s->get("AssocMode"));

    if (!defined $bottleid)
    {
        # Make sure the bottle gets an id
        # (in case of an upgrade from a pre-2.0 tree)
        $s->set("BottleID", CXUtils::get_unique_id($ENV{WINEPREFIX}));
    }
    if (($encoding || "ANSI_X3.4-1968") eq "ANSI_X3.4-1968")
    {
        # ANSI_X3.4-1968 is ASCII's little name so we assume that it's
        # going to be compatible with whatever encoding is used by
        # this system.
        $s->set("Encoding", CXUtils::get_system_encoding(1));
    }
    if (!$src->get_filename())
    {
        # Brand new cxbottle.conf, get MenuRoot from $productid.conf
        require CXConfig;
        my $cxconfig=CXConfig->new("$ENV{CX_ROOT}/etc/$productid.conf");
        my $menu_root=$cxconfig->get("BottleDefaults", "MenuRoot");
        $s->set("MenuRoot", $menu_root) if (defined $menu_root);
        my $menu_strip=$cxconfig->get("BottleDefaults", "MenuStrip");
        $s->set("MenuStrip", $menu_strip) if (defined $menu_strip);
    }

    $s = $src->get_section("EnvironmentVariables");
    $s = $src->add_section("EnvironmentVariables") if (!defined $s);

    if ($old_version lt "15.0.0")
    {
        # for CrossOver hack 12735
        $s->set("CX_REPORT_REAL_USERNAME", "yes");
        $s->remove_field("PULSE_LATENCY_MSEC");
    }

    # Do the final merge and write the new configuration file
    $dst->merge($src);
    $dst->write($filename);

    return ($old_version, $src);
}

sub upgrade_cxmenu_config()
{
    return if (!-f "$ENV{WINEPREFIX}/cxmenu.conf");

    # The whole bottle is locked so we don't need to lock cxmenu.conf
    require CXRWConfig;
    my $cxmenu=CXRWConfig->new("$ENV{WINEPREFIX}/cxmenu.conf");

    foreach my $section ($cxmenu->get_section_names())
    {
        if ($section !~ /\.lnk$/i)
        {
            my $new="$section.lnk";
            $cxmenu->rename_section($section, $new);
        }
    }
    $cxmenu->save();
}

sub upgrade($$$)
{
    my ($self, $cxconfig, $params)=@_;
    $@="";

    return undef if (!rename_fake_windows());

    # Upgrade the configuration files
    my ($old_version, $cxbottle)=upgrade_cxbottle($cxconfig, $params);

    # Grab all the Wine paths we'll need in one go
    my $username;
    my @wine_paths=("c:/Windows/Icons",
                    "c:/windows/system32/shdocvw.dll", # for run_inf()
                   );
    if ($old_version lt "06.0.0")
    {
        create_windows_label();
        push @wine_paths, "c:/Windows/Fonts", "c:/Windows/profiles/crossover";
        $username=(getpwuid($>))[0];
        push @wine_paths, "c:/Windows/profiles/$username" if ($username);
    }
    my @old_binaries=("c:/windows/notepad.exe",
                      "c:/windows/regedit.exe",
                      "c:/windows/system/rundll32.exe",
                      "c:/windows/system/ws2_32.dll"
                     );
    push @wine_paths, @old_binaries if ($old_version lt "06.0.1");

    my $winepath=shquote_string("$ENV{CX_ROOT}/bin/wine") .
                 " --no-convert --scope $params->{scope} --wl-app winepath.exe -- " .
                 join(" ", map { shquote_string($_) } @wine_paths);
    my %unix_paths;
    my $i=0;
    foreach my $path (cxbackquote("$winepath 2>/dev/null", 1))
    {
        chomp $path;
        $unix_paths{$wine_paths[$i]}=$path;
        cxlog("[$wine_paths[$i]] -> [$path]\n");
        $i++;
    }

    my $dir=$unix_paths{"c:/Windows/Fonts"};
    if ($old_version lt "06.0.0" and defined $dir and opendir(my $dh, $dir))
    {
        # We're not doing this in crossover.inf because this gets Wine
        # confused, causing it to build the old-style font metrics
        foreach my $dentry (readdir $dh)
        {
            if ($dentry =~ /\.(ttf|fon)$/i and -f "$dir/$dentry")
            {
                my $ref="$ENV{CX_ROOT}/share/wine/fonts/" . lc($dentry);
                if (-f $ref)
                {
                    cxlog("Deleting '$dir/$dentry'\n");
                    unlink "$dir/$dentry";
                }
            }
        }
        closedir($dh);
    }

    $dir=$unix_paths{"c:/Windows/profiles/crossover"};
    if ($old_version lt "06.0.0" and $username and defined $dir and !-e $dir)
    {
        my $profile=$unix_paths{"c:/Windows/profiles/$username"};
        if (defined $profile and -d $profile)
        {
            cxlog("Renaming '$profile' to 'crossover'\n");
            if (!rename $profile, $dir or !symlink "crossover", $profile)
            {
                cxlog("unable to move and symlink '$profile' to '$dir'\n");
            }
        }
    }

    my $reg_lines=[];
    if ($old_version lt "06.0.1")
    {
        foreach my $wine_path (@old_binaries)
        {
            my $unix_path=$unix_paths{$wine_path};
            next if (!defined $unix_path or !-f $unix_path);
            if (!cxsystem("fgrep -l libwine.so.1 " . shquote_string($unix_path) . " >/dev/null 2>&1"))
            {
                cxlog("Deleting '$unix_path'\n");
                unlink $unix_path;
            }
        }
    }

    if ($old_version lt "06.0.0")
    {
        if (cxsystem("$ENV{CX_ROOT}/bin/wine", "--wl-app", "rundll32.exe",
                     "--no-quotes", "--scope", $params->{scope},
                     "--desktop", "root",
                     "setupapi.dll,InstallHinfSection", "PreUpgrade", "128",
                     "$datadir/crossover.inf"))
        {
            $@="'rundll32 PreUpgrade crossover.inf' failed\n";
            return undef;
        }
    }
    if ($old_version lt "07.0")
    {
        # FIXME: It would be nicer to do it using crossover.inf but Wine's
        #        setupapi does not know how to recursively delete registry
        #        keys (see bug 13548).
        my $cmd=shquote_string("$ENV{CX_ROOT}/bin/wine") .
                " --scope $params->{scope} --wl-app regedit.exe -";
        cxlog("Piping into $cmd\n");
        if (open(my $regedit, "| $cmd"))
        {
            print $regedit "[-HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\Print\\Environments\\Windows 4.0\\Drivers]\n";
            close($regedit);
            if ($?)
            {
                $@="'$cmd' failed: $?\n";
                return undef;
            }
        }
    }
    if ($old_version lt "09.0")
    {
        # remove the Locale key in order to recreate the proper locale strings
        # don't do this with reg_lines as I want it to happen before the INF
        my $cmd=shquote_string("$ENV{CX_ROOT}/bin/wine") .
                " --scope $params->{scope} --wl-app regedit.exe -";
        cxlog("Piping into $cmd\n");
        if (open(my $regedit, "| $cmd"))
        {
            print $regedit "[HKEY_CURRENT_USER\\Control Panel\\International]\n";
            print $regedit "\"Locale\"=\"\"\n";
            close($regedit);
            if ($?)
            {
                $@="'$cmd' failed: $?\n";
                return undef;
            }
        }
    }
    return undef if (!run_inf($windows_version, $params->{scope}, 1, \%unix_paths));

    $dir=$unix_paths{"c:/Windows/Icons"};
    if (defined $dir and opendir(my $dh, $dir))
    {
        foreach my $dentry (readdir $dh)
        {
            if ($dentry !~ /^\.\.?$/ and -d "$dir/$dentry")
            {
                cxlog("Deleting the '$dir/$dentry' directory\n");
                require File::Path;
                if (!File::Path::rmtree("$dir/$dentry"))
                {
                    cxwarn("unable to delete the '$dir/$dentry' directory\n");
                }
            }
        }
        closedir($dh);
    }

    # Wine now has native support for $http_proxy
    if ($old_version lt "07.0" and defined $ENV{http_proxy})
    {
        push @{$reg_lines},
            "[HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings]\n",
            "\"ProxyServer\"=-\n",
            "\"ProxyEnable\"=-\n",
            "[HKEY_USERS\\.Default\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings]\n",
            "\"ProxyServer\"=-\n",
            "\"ProxyEnable\"=-\n";
    }

    if ($old_version lt "18.0.0" &&
        (-e "$ENV{WINEPREFIX}/drive_c/Program Files/Microsoft Office/Office15" ||
         -e "$ENV{WINEPREFIX}/drive_c/Program Files/Microsoft Office/Office16"))
    {
        # for bug 15944
        push @{$reg_lines},
            "[HKEY_CURRENT_USER\\Software\\Wine\\Direct2D]\n",
            "\"max_version_factory\"=dword:00000000\n";
    }

    if ($old_version lt "18.0.0" &&
        (-e "$ENV{WINEPREFIX}/drive_c/Program Files/Microsoft Office/Office14" ||
         -e "$ENV{WINEPREFIX}/drive_c/Program Files/Microsoft Office/Office15" ||
         -e "$ENV{WINEPREFIX}/drive_c/Program Files/Microsoft Office/Office16"))
    {
        # for bug 15944
        push @{$reg_lines},
            "[HKEY_CURRENT_USER\\Software\\Wine\\X11 Driver]\n",
            "\"ScreenDepth\"=\"32\"\n";
    }


    # Upgrade the registry
    if (@$reg_lines)
    {
        my $cmd=shquote_string("$ENV{CX_ROOT}/bin/wine") .
                " --scope $params->{scope} --wl-app regedit.exe -";
        cxlog("Piping into $cmd\n");
        cxlog(@$reg_lines);
        if (open(my $regedit, "| $cmd"))
        {
            print $regedit "REGEDIT4\n\n";
            print $regedit @$reg_lines;
            close($regedit);
            if ($?)
            {
                $@="'$cmd' failed: $?\n";
                return undef;
            }
        }
    }

    # Old versions used to hardcode the external browser / email tools names
    if ($old_version lt "07.0")
    {
        if (cxsystem("$ENV{CX_ROOT}/bin/wine", "--wl-app", "rundll32.exe",
                     "--no-quotes", "--scope", $params->{scope},
                     "--desktop", "root",
                     "setupapi.dll,InstallHinfSection", "WineBrowserUpgrade",
                     "128", "$datadir/crossover.inf"))
        {
            $@="'rundll32 WineBrowserUpgrade crossover.inf' failed\n";
            return undef;
        }
    }

    my $uassoc="";
    my $umenu="";
    my $unsplugin="";
    if ($old_version lt "05.0")
    {
        # If the same user who owns the bottle installed CrossOver,
        # then the legacy menus, associations and plugins have already been
        # removed. Otherwise we must do it.
        if (!-o $ENV{CX_ROOT})
        {
            cxsystem("$ENV{CX_ROOT}/bin/cxmenu", "--scope", $params->{scope},
                     "--removeall", "--pattern", "legacy", "--ignorelist", "");
            cxsystem("$ENV{CX_ROOT}/bin/cxassoc", "--scope", $params->{scope},
                     "--removeall", "--pattern", "legacy", "--ignorelist", "");
        }

        # Recreate the menus, associations and plugins from scratch
        $uassoc=$umenu=$unsplugin="sync";
    }
    if ($old_version lt "06.0.1")
    {
        # Reinstall the menus and associations because the icons moved around
        # For menus --removeall is needed to fix the implicit menus icons
        $uassoc.="+install";
        $umenu.="+removeall+install";
    }
    if ($old_version lt "10.0")
    {
        # The KDE association handling has changed significantly
        # so they have to be removed and recreated
        $uassoc.="+nukeall+install";
        # We also need to rebuild the menus
        upgrade_cxmenu_config();
        $umenu="+removeall+sync+install";
    }
    if ($old_version le "10.0.1")
    {
        # The XDG association handling has changed significantly
        # so they have to be removed and recreated
        $uassoc.="+nukeall+install";
    }
    if ($old_version lt "11.0")
    {
        # Handling of the menu icons has changed significantly
        # so they have to be removed and recreated
        $umenu.="+removeall+sync+install";
    }
    if ($old_version lt "12.0")
    {
        # The Mailcap MIME type handling has changed
        $uassoc.="+removeall+install";
        # The Windows script names have changed
        $umenu.="+removeall+install";
    }
    if ($old_version lt "12.5.1")
    {
        # The XDG data directories and Windows menu script names have changed
        $uassoc.="+removeall+install";
        $umenu.="+removeall+install";
    }
    if ($old_version lt "14.0.4")
    {
        # The XDG data directories have changed. Furthermore, due to a bug in
        # assocscan some associations were not detected. So re-sync.
        $uassoc.="+removeall+install+sync";
        $umenu.="+removeall+install";
    }
    if ($old_version lt "20.0")
    {
        # The Arch field often contained garbage and the StartupWMClass field
        # was not set.
        $umenu.="+removeall+sync+install";
    }

    my $bottle_mode=$ENV{CX_BOTTLE_MODE} || $cxbottle->get("Bottle", "AssocMode", "");
    my $installed=($bottle_mode =~ /^install$/i);
    if ($uassoc)
    {
        my @cmd=("$ENV{CX_ROOT}/bin/cxassoc", "--scope", $params->{scope});
        if ($installed)
        {
            if ($uassoc =~ /nukeall/)
            {
                # This action must be used when locate_gui.sh's arbitration
                # between association systems changes. Otherwise we risk not
                # removing associations for systems that were used but are now
                # in desktop_assoc_ignore_list. This task must be performed as
                # a separate step because of the --ignorelist parameter.
                cxsystem(@cmd, "--removeall", "--ignorelist", "");
                # No need to do a plain --removeall on top
                $uassoc =~ s/removeall//g;
            }
            push @cmd, "--removeall" if ($uassoc =~ /removeall/);
            push @cmd, "--install" if ($uassoc =~ /install/);
        }
        if ($uassoc =~ /sync/)
        {
            my $mode="mime;default=$default_eassocids;alternative=$alternative_eassocids";
            $mode =~ s/\./\\./g;
            push @cmd, "--sync", "--mode", $mode;
        }
        cxsystem(@cmd) if (@cmd ne 3);
    }
    $bottle_mode=$ENV{CX_BOTTLE_MODE} || $cxbottle->get("Bottle", "MenuMode", "");
    $installed=($bottle_mode =~ /^install$/i);
    if ($umenu)
    {
        my @cmd=("$ENV{CX_ROOT}/bin/cxmenu", "--scope", $params->{scope});
        if ($installed)
        {
            if ($umenu =~ /nukeall/)
            {
                # See the comments for the associations nukeall action.
                cxsystem(@cmd, "--removeall", "--ignorelist", "");
                $umenu =~ s/removeall//g;
            }
            push @cmd, "--removeall" if ($umenu =~ /removeall/);
            push @cmd, "--install" if ($umenu =~ /install/);
        }
        push @cmd, "--sync", "--mode", "install" if ($umenu =~ /sync/);
        cxsystem(@cmd) if (@cmd ne 3);
    }

    # Notify the bottle hooks
    require CXBottle;
    CXBottle::run_bottle_hooks(["upgrade-from", $old_version]);

    return 1;
}


#
# Bottle resync
#

sub needs_resync($$)
{
    # This type of bottle never needs to be resync-ed with an external source
    return 0;
}

return 1;
