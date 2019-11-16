package req nx
package req nx::serializer
package req xotcl::serializer

namespace eval ws::snapshot {
    nx::Class create Snapshot {
	#
	# Collect the following types of things in the workspace
	#
	:property {elements {
	    vars procs nx-objects xotcl-objects
	}}

	#
	# Set namespace to collect, global by default
	#
	:property {namespace ""}

	#
	# collector methods
	#
	:method "collect vars" {} {
	    # Get vars from specified namespace
	    return [info vars "${:namespace}::*"]
	}

	:method "collect procs" {} {
	    # Get vars from specified namespace
	    return [list \
			{*}[info procs "${:namespace}::*"] \
			{*}[nx::Object ::nsf::methods::object::info::lookupmethods "${:namespace}::*"] \
		       ]
	}
	:method "collect nx-objects" {} {
	    # Get objects from specified namespace
	    return [lmap o [nx::Object info instances -closure ${:namespace}::*] {
		#
		# Filter slot objects
		#
		if {[string match *::slot::* $o]
		    || [::nx::isSlotContainer $o]
		} continue
		set o
	    }]
	}

	:method "collect xotcl-objects" {} {
	    # Get objects from specified namespace
	    return [lmap o [xotcl::Object info instances -closure ${:namespace}::*] {
		#
		# Filter slot objects
		#
		if {[string match *::slot::* $o]
		    || [::nx::isSlotContainer $o]
		} continue
		set o
	    }]
	}

	:public method "collect all" {} {
	    foreach e ${:elements} { dict set d $e [:collect $e] }
	    return $d
	}

	#
	# save methods
	#
	:method "save vars" {vars} {
	    set result ""
	    foreach e $vars {
		append result [list set $e [set $e]] \n
	    }
	    return $result
	}
	:method "save procs" {procs} {
	    set result ""
	    foreach e $procs {
		if {[info procs $e] ne ""} {
		    append result [list proc $e [info args $e] [info body $e]] \n
		} else {
		    append result [::nsf::cmd::info definition $e] \n
		}
	    }
	    return $result
	}
	:method "save nx-objects" {objects} {
	    set s [::nx::serializer::Serializer new]
	    foreach oss [::nx::serializer::ObjectSystemSerializer info instances] {
		$oss registerSerializer $s $objects
	    }
	    set result [$s serialize-objects $objects 0]
	    $s destroy
	    return $result
	}
	:method "save xotcl-objects" {objects} {
	    set s [::nx::serializer::Serializer new]
	    foreach oss [::nx::serializer::ObjectSystemSerializer info instances] {
		$oss registerSerializer $s $objects
	    }
	    set result [$s serialize-objects $objects 0]
	    $s destroy
	    return $result
	}

	:method listDiff {a b} {
	    #
	    # Compute differences between dicts
	    #
	    return [lmap x $a {if {$x in $b} continue; set x}]
	}

	:public method diff {} {
	    #
	    # Compute the difference of the current workspace with the
	    # values at snapshot creation time.
	    #
	    set current [:collect all]
	    foreach e ${:elements} {
		#puts "START $e: [llength [dict get ${:start} $e]]"
		#puts "NOW   $e: [llength [dict get $current $e]]"
		dict set diff $e [:listDiff [dict get $current $e] [dict get ${:start} $e]]
	    }
	    return $diff
	}

	:public method get_delta {} {
	    #
	    # Return a Tcl command which can be evaluated to reconstuct
	    # the difference between the start of the snapshot and the
	    # current state.
	    #
	    set diff [:diff]
	    set result ""
	    foreach e ${:elements} {
		append result [:save $e [dict get $diff $e]]
	    }
	    return $result

	}
	:method init {} {
	    set :start [:collect all]
	}
    }
}
