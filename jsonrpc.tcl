#
# Copyright 2017 Matthijs Bos <matthijs_vlaarbos@hotmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

package require Tcl 8.5
package require fpgaedu::json 1.0

package provide fpgaedu::jsonrpc 1.0

namespace eval ::fpgaedu::jsonrpc {
    
}

proc ::fpgaedu::jsonrpc::handle {mapping channel} {

    set id null
    set idSchema null

    if {[catch {
        # read request data
        set request [chan read $channel]
        
        # parse request data
        lassign [::fpgaedu::jsonrpc::parseRequest request] data schema

        # validate request
        ::fpgaedu::jsonrpc::validateRequest $data $schema

        # extract relevant request members
        set method [dict get $data method]
        set id [dict get $data id]
        set idSchema [dict get $schema id]
        set params {}
        if {dict contains $data params} {
            set params [dict get $data params]
        }

        # find proper handler
        set handler [::fpgaedu::jsonrpc::findHandler $mapping $method]

        # execute handler
        set result [$handler $params]

        set response [::fpgaedu::jsonrpc::stringifyResult $result $result-schema \
                $id $idSchema] 
       
        
    } errorResult]} {
        # catch error throws in section above
        dict set error code -32603
        dict set error message "Internal error"
        dict set error data {}
        set errorDataSchema {}

        if {[dict exists $errorResult code] 
                && [dict exists $errorResult message]} {
            # $errorResult is probably the result of a call to the 
            # ::fpgaedu::jsonrpc::throw proc
            dict set error code [dict get $errorResult code]
            dict set error message [dict get $errorResult message]

            if {dict exists $errorResult data} {
                dict set error data [dict get $errorResult data]
                set errorDataSchema {}
                set 
            }
        } else {
            dict set error data errorResult
            dict set errorDataSchema string
        }

        set response [::fpgaedu::jsonrpc::stringifyError $error $errorDataSchema $id $idSchema]
    }
    chan puts $channel response

    chan close $channel
}

proc ::fpgaedu::jsonrpc::parseRequest {data} {

    if {[catch {
        set json [::json::parse $data 0]
        set schema [::json::parseSchema $data 0]
    } err ]} {
        ::fpgaedu::jsonrpc::throwParseError $err
    }

    return [list $json $schema]
}

proc ::fpgaedu::jsonrpc::validateRequest {data schema} {
    # check jsonrpc member
    if {![dict exists $data jsonrpc]} {
        ::fpgaedu::jsonrpc::throwInvalidRequest "Missing member jsonrpc"
    }
    if {[dict get $schema jsonrpc] != string} {
        ::fpgaedu::jsonrpc::throwInvalidRequest "Illegal type for member jsonrpc"
    }
    if {[dict get $data jsonrpc] != "2.0"} {
        ::fpgaedu::jsonrpc::throwInvalidRequest "Illegal value for member jsonrpc"
    }
 
    #check method member
    if {![dict exists $data method]} {
        ::fpgaedu::jsonrpc::throwInvalidRequest "Missing member method"
    }
    if {[dict get $schema method] != string} {
        ::fpgaedu::jsonrpc::throwInvalidRequest "Illegal type for member method"
    }
    if {[dict get $data method] == ""} {
        ::fpgaedu::jsonrpc::throwInvalidRequest "Illegal value for member method"
    }

    #check id member 
    if {[dict exists $data id] \
            && [[dict get $schema id] ni {string number null}]} {

        ::fpgaedu::jsonrpc::throwInvalidRequest "Illegal type for id"
    }
}

proc ::fpgaedu::jsonrpc::stringifyResult {data dataSchema id idSchema} {

   dict set response jsonrpc 2.0
   dict set response id $id
   dict set response result $data

   dict set schema jsonrpc string
   dict set schema id $idSchema
   dict set schema result $dataSchema

   if {[dict get $response result] == {}} {
       dict set response result null
       dict set schema result null
   }

   ::json::stringify $response 0 $schema 
}

proc ::fpgaedu::jsonrpc::stringifyError {error errorDataSchema id idSchema} {

   dict set response jsonrpc 2.0
   dict set response id $id
   dict set response error $error 

   dict set schema jsonrpc string
   dict set schema id $idSchema
   dict set schema error code number
   dict set schema error message string
   if {dict exists $error data} {
       dict set schema error data $errorDataSchema
   }

   return ::json::stringify $response 0 $schema

}

proc ::fpgaedu::jsonrpc::findHandler {mapping method} {
    
    if {[catch {
        set handler [dict get $mapping $method]
    } errorResult]} {
        ::fpgaedu::jsonrpc::throwUnknownMethod "Unknown method $method"
    }

    return $handler
}

proc ::fpgaedu::jsonrpc::throw {code message {data {}} {dataSchema {}}} {

    dict set result code $code
    dict set result message $message

    if {$data ne {}} {
        dict set result data $data 
        if {$data schema ne ""} {
            dict set result dataSchema $dataSchema
        }
    }

    error $result
}

proc ::fpgaedu::jsonrpc::throwParseError {message {data ""} {dataSchema ""}} {
    ::fpgaedu::jsonrpc::throw -32700 $message $data $dataSchema
}

proc ::fpgaedu::jsonrpc::throwInvalidRequest {message {data ""} {dataSchema ""}} {
    ::fpgaedu::jsonrpc::throw -32600 $message $data $dataSchema
}

proc ::fpgaedu::jsonrpc::throwUnknownMethod {message {data ""} {dataSchema ""}} {
    ::fpgaedu::jsonrpc::throw -32601 $message $data $dataSchema
}

proc ::fpgaedu::jsonrpc::throwInvalidParams {message {data ""} {dataSchema ""}} {
    ::fpgaedu::jsonrpc::throw -32602 $message $data $dataSchema
}

proc ::fpgaedu::jsonrpc::throwInternalError {message {data ""} {dataSchema ""}} {
    ::fpgaedu::jsonrpc::throw -32603 $message $data $dataSchema
}
