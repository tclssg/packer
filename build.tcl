#!/usr/bin/env tclsh
# Producer, a Starpack creation script.
# Copyright (C) 2015 Danyil Bohdan.
# License: MIT

package require platform

set packerPath [file dirname [file dirname [file normalize $argv0/___]]]
source [file join $packerPath packer.tcl]

set tclkits [::packer::sl {
    macosx          tclkit-8.6.3-macosx10.5-ix86+x86_64
    linux-ix86      tclkit-8.6.3-rhel5-ix86
    linux-x86_64    tclkit-8.6.3-rhel5-x86_64
    win32           tclkit-8.6.3-win32.exe
}]

proc get-tclkit-for-currrent-platform {} {
    global tclkits
    dict for {key value} $tclkits {
        if {[string compare -length [string length $key] \
                $key [::platform::generic]] == 0} {
            return $value
        }
    }
    error "Unknown platform: [::platform::generic]"
}

set buildTclkit [get-tclkit-for-currrent-platform]

foreach targetTclkit [dict values $tclkits] {
    set buildOptions $::packer::defaultBuildOptions

    #dict set buildOptions sourceRepository [file normalize ..]

    file tempfile buildPath packer-build
    puts $buildPath
    file delete $buildPath
    dict set buildOptions buildPath $buildPath

    dict set buildOptions packerPath $packerPath
    dict set buildOptions buildTclkit $buildTclkit
    dict set buildOptions targetTclkit $targetTclkit
    if {$targetTclkit ne $buildTclkit} {
        dict unset buildOptions testCommand
    }
    ::packer::build {*}$buildOptions
}
