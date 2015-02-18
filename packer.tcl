#!/usr/bin/env tclsh
# Packer, a tool for creating Starpacks out of Git repositories.
# Copyright (C) 2015 Danyil Bohdan.
# License: MIT

package require Tcl 8.5

namespace eval ::packer {
    variable version 0.3
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
        buildTclkit         {tclkit-8.6.3-rhel5-x86_64}

        # The Tclkit to use as the runtime in the Starpack.
        targetTclkit        {tclkit-8.6.3-rhel5-x86_64}

        # SDX Starkit file.
        sdx                 {sdx-20110317.kit}

        # Tcllib archive file.
        tcllib              {Tcllib-1.16.tar.gz}

        # The Git repository to clone. Can be local or remote.
        sourceRepository    {https://github.com/tclssg/tclssg}

        # The directory that will appear once the sourceRepository is cloned.
        projectDir          {tclssg}

        # The filename of the Starpack to create. Normally should not include an
        # extension -- see "suffix" below for how extensions are added
        # automatically.
        targetFilename      "tclssg"

        # Which file within the projectDir the Starpack should sourced on start.
        fileToSource        {ssg.tcl}

        # An anonymous function to be run when the the Starpack starts on
        # Windows. If set and not empty it is run *instead of* simply sourcing
        # the file in fileToSource like on other platforms.
        windowsScript       {{fileToSource argv0 argv} {
            # This anonymous function sets up the console window, creates a new
            # thread for Tclssg and makes sure Tclssg's output goes in the said
            # console window, asynchronously.
            console show
            console title Tclssg

            # Quit when the console window is closed.
            console eval {
                wm protocol . WM_DELETE_WINDOW {
                    consoleinterp eval {
                        exit 0
                    }
                }
                set ::tk::console::maxLines 5000
            }

            # Run Tclssg in a separate thread.
            package require Thread
            set tid [::thread::create]
            ::thread::send $tid [list source $fileToSource]
            ::thread::send $tid [list set argv0 $argv0]
            ::thread::send $tid [list set argv $argv]
            ::thread::send $tid [list apply {{consoleThread} {
                rename puts puts-old
                proc puts args [list apply {{consoleThread} {
                    upvar 1 args args
                    if {[llength $args] == 1} {
                        ::thread::send $consoleThread [list puts {*}$args]
                    } else {
                        puts-old {*}$args
                    }
                }} $consoleThread]
            }} [::thread::id]]
            ::thread::send -async $tid {::tclssg::main $argv0 $argv} done
            vwait done
        }}

        # Command line options to run the Starpack with once it has been built.
        # Unset to not test. Obviously, this won't work across incompatible
        # platforms.
        testCommand         {version}

        # The string to append to the targetFilename. If not set everything
        # after the first dash in the targetTclkit's rootname is used. E.g, if
        # targetTclkit is "tclkit-8.6.3-win32.exe" the default suffix will be
        # "-8.6.3-win32.exe".
        # suffix {}
    }]
}

# Build a Starpack. $args is a directory; see variable defaultBuildOptions for
# keys.
proc ::packer::build args {
    # Parse command line arguments.
    dict for {key value} $args {
        puts [format {%23s: %s} $key $value]
        set $key $value
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
            set commit [git rev-parse HEAD]
        }

        if {![info exists suffix]} {
            set suffix -[string range $commit 0 9]-$targetTclkit
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
                        package require Tk
                        wm withdraw .
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
            commit $commit.
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
