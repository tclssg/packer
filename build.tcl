#!/usr/bin/env tclsh
# Packer, a tool for creating Starpacks out of Git repositories.
# Copyright (c) 2015, 2017, 2018 dbohdan.
# License: MIT

# Usage: build.tcl [revision [key value ..]]

package require Tcl 8.6
package require platform

set packerPath [file dirname [file dirname [file normalize $argv0/___]]]
source [file join $packerPath packer.tcl]

set tclkits [::packer::sl {
    macosx          tclkit-8.6.3-macosx10.5-ix86+x86_64
    linux-ix86      tclkit-8.6.3-rhel5-ix86
    linux-x86_64    tclkit-8.6.3-rhel5-x86_64
    win32           tclkit-8.6.3-win32.exe
}]

proc tclkit-for-current-platform {} {
    dict for {key value} $::tclkits {
        if {[string compare -length \
                            [string length $key] \
                            $key [::platform::generic]] == 0} {
            return $value
        }
    }
    error [list unknown platform [::platform::generic]]
}

proc usage {} {
    set me [file tail [info script]]
    puts stderr "usage: $me \[revision \[key value ...\]\]"
}

proc temp-path template {
    close [file tempfile path $template]
    file delete $path
    return $path
}

proc parse-argv argv {
    set options {}

    if {$argv in {-h -help --help /?} ||
        ([llength $argv] > 0 && [llength $argv] % 2 == 0)} {
        usage
        exit [expr {[llength $argv] != 1}]
    }

    set options [lassign $argv revision]
    if {$revision ne {}} {
        dict set options revision $revision
    }

    return $options
}

dict set options buildTclkit    [tclkit-for-current-platform]
dict set options packerPath     $packerPath
dict set options targetTclkits  [dict values $tclkits]
set options [dict merge $options [parse-argv $argv]]

if {![dict exists $options buildPath]} {
    dict set options buildPath [temp-path packer-build]
}

::packer::build {*}$options
