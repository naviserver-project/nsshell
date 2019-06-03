package req nx
package req nx::serializer

namespace eval ws_manager {
    nx::Class create Snapshot {
        #
        # Collect the following types of things in the workspace
        #
        :property {elements {
            global-vars nx-objects
        }}

        #
        # collector methods
        # 
        :method "collect global-vars" {} {
            return [info vars ::*]
        }
        :method "collect nx-objects" {} {
            return [lmap o [nx::Object info instances -closure] {
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
        :method "save global-vars" {vars} {
            set result ""
            foreach e $vars {
            append result [list set $e [set $e]] \n
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

        #
        # Compute differences between dicts
        #
        :method listDiff {a b} {
            return [lmap x $a {if {$x in $b} continue; set x}]
        }
        :public method diff {} {
            set current [:collect all]
            foreach e ${:elements} {
            #puts "START $e: [llength [dict get ${:start} $e]]"
            #puts "NOW   $e: [llength [dict get $current $e]]"
            dict set diff $e [:listDiff [dict get $current $e] [dict get ${:start} $e]]
            }
            return $diff
        }

        
        #
        # Return a Tcl command which can be evaluated to reconstuct
        # the difference between the start of the snapshot and the
        # current state.
        #
        :public method dump {} {
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