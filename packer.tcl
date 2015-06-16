#!/usr/bin/env tclsh
# Packer, a tool for creating Starpacks out of Git repositories.
# Copyright (C) 2015 Danyil Bohdan.
# License: MIT

package require Tcl 8.5

namespace eval ::packer {
    variable version 0.6
}

proc ::packer::init {} {
    variable defaultBuildOptions [::packer::sl {
        # Where Packer's files are located.
        packerPath          [pwd]

        # The path to the temporary directory in which the Starpacks are built.
        # Can be relative (to packerPath) or absolute.
        buildPath           build

        # The path where to place the resulting Starpack.
        # Can be relative (to packerPath) or absolute.
        artifactsPath       artifacts

        # The Tclkit to run SDX with.
        buildTclkit         tclkit-8.6.3-rhel5-x86_64

        # The Tclkit to use as the runtime in the Starpack.
        targetTclkit        tclkit-8.6.3-rhel5-x86_64

        # SDX Starkit file.
        sdx                 sdx-20110317.kit

        # Tcllib archive file.
        tcllib              Tcllib-1.16.tar.gz

        # The Git repository to clone. Can be local or remote.
        sourceRepository    https://github.com/tclssg/tclssg

        # The name of the commit or tag to check out of the repository. Blank
        # for HEAD. Leave at %AUTO% for the latest HEAD commit.
        checkout            %AUTO%

        # The directory that will appear once the sourceRepository is cloned.
        projectDir          tclssg

        # The filename of the Starpack to create. Normally should not include an
        # extension -- see "suffix" below for how extensions are added
        # automatically.
        targetFilename      tclssg

        # Which file within the projectDir the Starpack should sourced on start.
        fileToSource        ssg.tcl

        # An anonymous function to be run when the the Starpack starts on
        # Windows. If set and not empty it is run *instead of* simply sourcing
        # the file in fileToSource like on other platforms.
        windowsScript       {{fileToSource argv0 argv} {
            source $fileToSource
            ::tclssg::main $argv0 $argv
        }}

        # Command line options to run the Starpack with once it has been built.
        # Unset to not test. Obviously, this won't work across incompatible
        # platforms.
        testCommand         version

        # The string to append to the targetFilename. If set to %AUTO%
        # everything after the first dash in the targetTclkit's rootname is
        # used. E.g, if targetTclkit is "tclkit-8.6.3-win32.exe" the default
        # suffix will be "-8.6.3-win32.exe".
        suffix              %AUTO%
    }]
}

proc ::packer::sha-1? s {
    return [regexp {^[a-fA-F0-9]{40}$} $s]
}

proc ::packer::auto? key {
    return [expr { $key eq {%AUTO%} }]
}


# Build a Starpack. $args is a directory; see variable defaultBuildOptions for
# keys.
proc ::packer::build args {
    # Parse $args.
    dict for {key _} $::packer::defaultBuildOptions {
        if {[dict exists $args $key]} {
            set value [dict get $args $key]
            puts [format {%23s: %s} $key $value]
            set $key $value
        }
    }

    # Defaults and mutation ahead.
    set buildPath [file join $packerPath $buildPath]
    set artifactsPath [file join $packerPath $artifactsPath]

    # Define procs for running external commands.
    foreach {procName command} [list \
        git git \
        tar tar \
        tclkit [file join . $buildTclkit] \
    ] {
        proc ::packer::$procName args [list apply {{command} {
            package require platform
            upvar 1 args args
            exec -ignorestderr -- {*}$command {*}$args
        }} $command]
    }

    # Build start.
    file delete -force $buildPath
    file mkdir $buildPath

    with-path $buildPath {
        git clone $sourceRepository
        with-path $projectDir {
            if {[auto? $checkout]} {
                set checkout [git rev-parse HEAD]
            } else {
                git checkout $checkout
            }
        }

        if {[auto? $suffix]} {
            # Abbreviate SHA-1 sums.
            if {[sha-1? $checkout]} {
                set suffix -[string range $checkout 0 9]-$targetTclkit
            } else {
                set suffix -$checkout-$targetTclkit
            }
        }

        foreach file [list $buildTclkit $targetTclkit $sdx $tcllib] {
            file copy -force [file join $packerPath $file] .
        }
        file attributes $buildTclkit -permissions +x

        file rename $projectDir "${projectDir}.vfs"

        # Create the file main.tcl to start $fileToSource.
        write-file [file join "${projectDir}.vfs" main.tcl] [list \
            apply {{fileToSource windowsScript} {
                global argv
                global argv0
                global tcl_platform

                package require starkit

                if {[starkit::startup] ne "sourced"} {
                    if {($tcl_platform(platform) eq "windows") &&
                            ($windowsScript ne "")} {
                        apply $windowsScript \
                                [file join $starkit::topdir $fileToSource] \
                                $argv0 \
                                $argv
                    } else {
                        source [file join $starkit::topdir $fileToSource]
                    }
                }
            }} $fileToSource \
                    [expr {[info exists windowsScript] ? $windowsScript : ""}]
        ]

        # Unpack Tcllib and install it in lib/tcllib subdirectory of the Starkit
        # VFS.
        tar zxvf $tcllib

        with-path [regsub {.tar.gz$} $tcllib {}] {
            puts [exec -- \
                    tclsh ./installer.tcl -no-wait -no-gui -no-html -no-nroff \
                    -no-examples -no-apps -pkgs -pkg-path \
                    [file join $buildPath "${projectDir}.vfs" lib tcllib]]
        }

        # Wrap the Starpack. We make a temporary copy of the targetTclkit
        # in case it is the same as buildTclkit, which we wouldn't be able to
        # read.
        file copy $targetTclkit "${targetTclkit}.temp"
        tclkit $sdx wrap $targetFilename -runtime "${targetTclkit}.temp"
        file delete "${targetTclkit}.temp"

        # Run the test command.
        if {[info exists testCommand]} {
            file attributes $targetFilename -permissions +x
            puts [exec -- [file join . $targetFilename] {*}$testCommand]
        }

        # Store the build artifact.
        file mkdir $artifactsPath
        set artifactFilename "$targetFilename$suffix"
        file copy -force $targetFilename \
                [file join $artifactsPath $artifactFilename]

        # Remove build directory.
        file delete -force $buildPath

        # Record build information in a Tcl-readable format.
        write-file [file join $artifactsPath "$artifactFilename.txt"] [sl {
            $artifactFilename built [utc-date-time] from $sourceRepository
            checkout $checkout.
        }]\n
    }
}

proc ::packer::utc-date-time {} {
    return [clock format [clock seconds] \
            -format {%Y-%m-%d %H:%M:%S UTC} -timezone UTC]
}

# Write $content to file $fname.
proc ::packer::write-file {fname content {binary 0}} {
    set fpvar [open $fname w]
    if {$binary} {
        fconfigure $fpvar -translation binary
    }
    puts -nonewline $fpvar $content
    close $fpvar
}

# Run $code in directory $path.
proc ::packer::with-path {path code} {
    set prevPath [pwd]
    cd $path
    uplevel 1 $code
    cd $prevPath
}

# Parse scripted list.
proc ::packer::sl script {
    # By Poor Yorick. From http://wiki.tcl.tk/39972.
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
