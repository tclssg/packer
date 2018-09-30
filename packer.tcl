#!/usr/bin/env tclsh
# Packer, a tool for creating Starpacks out of Git repositories.
# Copyright (c) 2015, 2017, 2018 dbohdan.
# License: MIT

package require Tcl 8.6

namespace eval ::packer {
    variable version 0.7.0
}

proc ::packer::init {} {
    variable defaultBuildOptions [sl {
        # Where Packer's files are located.
        packerPath          [pwd]

        # The path to the temporary directory in which the Starpacks are to be
        # built.
        # Can be relative (to packerPath) or absolute.
        buildPath           build

        # The path where to place the built Starpacks.
        # Can be relative (to packerPath) or absolute.
        artifactsPath       artifacts

        # The Tclkit with which to run SDX.
        buildTclkit         tclkit-8.6.3-rhel5-x86_64

        # A list of the Tclkits to use as Starpack runtimes.
        targetTclkits       tclkit-8.6.3-rhel5-x86_64

        # The SDX Starkit file.
        sdx                 sdx-20110317.kit

        # The Tcllib archive file.
        tcllib              Tcllib-1.16.tar.gz

        # The Git repository to clone.  Can be local or remote.
        sourceRepository    https://github.com/tclssg/tclssg

        # The name of the commit, branch, or tag to check out of the repository.
        revision            master

        # The directory that will appear once the sourceRepository is cloned.
        projectDir          tclssg

        # The filename of the Starpack to create.  Normally should not include
        # an extension -- see the "suffix" option below for how extensions are
        # automatically added.
        targetFilename      tclssg

        # Which file within the projectDir the Starpack should source on start.
        fileToSource        ssg.tcl

        # A script to evaluate when the Starpack starts on Windows.  If set and
        # not empty it is run *instead of* sourcing the file in fileToSource
        # like on other platforms.
        windowsScript       {
            source $argv0
            ::tclssg::main $argv0 $argv
        }

        # The command line options to run the Starpack with once it has been
        # built.  Unset to not test.  This will not work across incompatible
        # platforms.
        testCommand         version

        # The string to append to the targetFilename.  If set to %AUTO%,
        # everything after the first dash in the targetTclkit's rootname is
        # used.  E.g, if targetTclkit is "tclkit-8.6.3-win32.exe", then the
        # automatic suffix will be "-8.6.3-win32.exe".
        suffix              %AUTO%
    }]
}

proc ::packer::sha-1? s {
    return [regexp {^[a-fA-F0-9]{40}$} $s]
}

proc ::packer::auto? key {
    return [expr { $key eq {%AUTO%} }]
}

proc ::packer::run args {
    return [exec -ignorestderr -- {*}$args]
}

proc ::packer::opt {key {default %NONE%}} {
    upvar 1 options options
    if {[dict exists $options $key]} {
        return [dict get $options $key]
    } elseif {$default ne {%NONE%}} {
        return $default
    } else {
        error [list no key $key in options]
    }
}

# Build Starpacks.  $args is a dictionary; see the variable defaultBuildOptions
# for the keys.
proc ::packer::build args {
    # Parse $args.
    set options [dict merge $::packer::defaultBuildOptions $args]
    dict for {key value} $options {
        puts [format {%-18s %s} $key [list $value]]
    }

    set fullBuildPath [file join [opt packerPath] [opt buildPath]]
    set fullArtifactsPath [file join [opt packerPath] [opt artifactsPath]]

    # Build start.
    file delete -force $fullBuildPath
    file mkdir $fullBuildPath

    with-path $fullBuildPath {
        run git clone [opt sourceRepository]
        with-path [opt projectDir] {
            run git checkout [opt revision]
            set commit [run git rev-parse HEAD]
        }

        foreach path [list [opt buildTclkit] \
                           [opt sdx] \
                           [opt tcllib] \
                           {*}[opt targetTclkits]] {
            file copy -force [file join [opt packerPath] $path] .
        }
        catch { file attributes [opt buildTclkit] -permissions +x }

        file mkdir vfs
        write-file vfs/git-commit $commit
        file rename [opt projectDir] vfs/app

        # Create the file main.tcl to start fileToSource.
        set mainScript [regsub -all {\n            } [format {
            package require starkit

            if {[starkit::startup] ne "sourced"} {
                set argv0 [file join $starkit::topdir app %s]
                if {$tcl_platform(platform) eq "windows"} {
                    eval %s
                } else {
                    source $argv0
                }
            }
        } [list [opt fileToSource]] [list [opt windowsScript]]] \n]
        write-file vfs/main.tcl $mainScript

        # Unpack Tcllib and install it in the subdirectory lib/tcllib of the
        # Starkit VFS.
        run tar zxf [opt tcllib]
        with-path [regsub {.tar.gz$} [opt tcllib] {}] {
            run {*}[sl {
                >@ stdout
                [file join .. [opt buildTclkit]]
                ./installer.tcl -no-wait
                                -no-gui
                                -no-html
                                -no-nroff
                                -no-examples
                                -no-apps
                                -pkgs
                                -pkg-path [file join $fullBuildPath \
                                                     vfs/lib/tcllib]
            }]
        }

        # Wrap the Starpack.  We make a temporary copy of each targetTclkit in
        # case it is the same as the buildTclkit, which we may not be able to
        # read.
        foreach targetTclkit [opt targetTclkits] {
            puts stderr [list building starpack with runtime $targetTclkit]
            file copy $targetTclkit ${targetTclkit}.temp
            run [file join . [opt buildTclkit]] \
                [opt sdx] wrap [opt targetFilename] \
                               -vfs vfs \
                               -runtime ${targetTclkit}.temp
            file delete ${targetTclkit}.temp
            # Run the test command.
            if {[info exists testCommand]} {
                file attributes [opt targetFilename] -permissions +x
                puts [exec -- [file join . [opt targetFilename] \
                                           {*}[opt testCommand]]]
            }

            if {[auto? [opt suffix]]} {
                # Abbreviate commit checksum.
                set fullSuffix -[opt revision]-[string range $commit 0 9]
                append fullSuffix -$targetTclkit
            } else {
                set fullSuffix [opt suffix]
            }

            # Store the build artifact.
            file mkdir $fullArtifactsPath
            set artifactFilename [opt targetFilename]$fullSuffix
            file copy -force [opt targetFilename] \
                             [file join $fullArtifactsPath $artifactFilename]

            # Record build information in a Tcl-readable format.
            write-file [file join $fullArtifactsPath \
                                  ${artifactFilename}.txt] [sl {
                $artifactFilename
                built [utc-date-time]
                from [opt sourceRepository]
                revision [opt revision]
                commit $commit
            }]\n
        }

        # Remove build directory.
        file delete -force $fullBuildPath
    }
}

proc ::packer::utc-date-time {} {
    return [clock format [clock seconds] \
                         -format {%Y-%m-%d %H:%M:%S UTC} \
                         -timezone UTC]
}

# Write $content to the file $path.
proc ::packer::write-file {path content {binary 0}} {
    set ch [open $path w]
    if {$binary} {
        fconfigure $ch -translation binary
    }
    puts -nonewline $ch $content
    close $ch
}

# Run $code in the directory $path.
proc ::packer::with-path {path code} {
    set prevPath [pwd]
    try {
        cd $path
        uplevel 1 $code
    } finally {
        cd $prevPath
    }
}

# Parse a scripted list.
proc ::packer::sl script {
    # By Poor Yorick. From https://tcl.wiki/39972.
    set res {}
    set parts {}
    foreach part [split $script \n] {
        lappend parts $part
        set part [join $parts \n]
        #add the newline that was stripped because it can make a difference
        if {[info complete $part\n]} {
            set parts {}
            set part [string trim $part]
            if {$part eq {}} {
                continue
            }
            if {[string index $part 0] eq {#}} {
                continue
            }
            #Here, the double-substitution via uplevel is intended!
            lappend res {*}[uplevel list $part]
        }
    }
    if {$parts ne {}} {
        error [list {incomplete parts} [join $parts]]
    }
    return $res
}

::packer::init
