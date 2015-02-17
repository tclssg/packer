#!/usr/bin/env tclsh
# Producer, a Starpack creation script.
# Copyright (C) 2015 Danyil Bohdan.
# License: MIT

set packerPath [file dirname [file dirname [file normalize $argv0/___]]]
source [file join $packerPath packer.tcl]

foreach targetTclkit {
    tclkit-8.6.3-macosx10.5-ix86+x86_64
    tclkit-8.6.3-rhel5-ix86
    tclkit-8.6.3-rhel5-x86_64
    tclkit-8.6.3-win32.exe
} {
    set buildOptions $::packer::exampleBuildOptions
    dict set buildOptions packerPath $packerPath
    dict set buildOptions targetTclkit $targetTclkit
    dict unset buildOptions testCommand
    ::packer::build {*}$buildOptions
}
