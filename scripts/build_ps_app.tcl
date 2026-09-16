################################################################################
# xsct batch: build OCM GEM3 L3 app from firmware/netsec.xsa
#   xsct scripts/build_ps_app.tcl
################################################################################
set repo [file normalize [file join [file dirname [info script]] ..]]
set xsa  [file join $repo firmware netsec.xsa]
set ws   [file join $repo firmware vitis_ws]
set src  [file join $repo firmware netsec_l3_gem3.c]
set ld   [file join $repo firmware lscript_ocm.ld]

if {![file exists $xsa]} { error "missing $xsa — run scripts/build.tcl first" }
if {![file exists $src]} { error "missing $src" }

file mkdir $ws
setws $ws

if {[catch {platform remove netsec_plat} e]} { puts "INFO: no old platform ($e)" }
platform create -name netsec_plat -hw $xsa -proc psu_cortexa53_0 -os standalone
platform generate

if {[catch {app remove netsec_l3} e]} { puts "INFO: no old app ($e)" }
app create -name netsec_l3 -platform netsec_plat -domain standalone_domain \
    -template {Empty Application} -lang C

set app_src [file join $ws netsec_l3 src]
file mkdir $app_src
file copy -force $src [file join $app_src netsec_l3_gem3.c]
file copy -force $ld  [file join $app_src lscript.ld]
catch {file delete -force [file join $app_src dummy.c]}
catch {file delete -force [file join $app_src helloworld.c]}

# Vitis 2020.1: import + set linker script
catch {importsources -name netsec_l3 -path $app_src}
catch {app config -name netsec_l3 linker-script [file join $app_src lscript.ld]}

catch {app build -name netsec_l3}
set elf [file join $ws netsec_l3 Debug netsec_l3.elf]
if {![file exists $elf]} {
    puts "INFO: xsct app build missed ELF, falling back to link_ps_app.bat"
    set bat [file join $repo scripts link_ps_app.bat]
    if {[catch {exec $bat} e]} { puts $e }
}
if {![file exists $elf]} { error "ELF not produced" }
file copy -force $elf [file join $repo firmware netsec_l3.elf]
puts "INFO: ELF -> firmware/netsec_l3.elf"
