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
#

package require Tcl 8.5
package require base64 2.4
package require fileutil 1.13.5

package require fpgaedu::jsonrpc 1.0
package require fpgaedu::json 2.0
package require fpgaedu::vivado 1.0

package provide fpgaedu::vivadoserver 1.0

namespace eval ::fpgaedu::vivadoserver {

    namespace export vivadoserver

    namespace import ::fpgaedu::jsonrpc::jsonrpc
    namespace import ::fpgaedu::json::json
    namespace import ::fpgaedu::vivado::vivado

    variable rpcConfig 
    jsonrpc map rpcConfig program ::rpcProgramHandler
    # jsonrpc map rpcConfig ::rpcGetHardwareInfoHandler getHardwareInfo

    set commandMap {
        start ::fpgaedu::vivadoserver::Start
    }

    namespace ensemble create \
            -map $commandMap

    namespace ensemble create \
            -command vivadoserver \
            -map $commandMap
}

proc ::fpgaedu::vivadoserver::rpcProgramHandler {paramsJson} {
    # validate params
    if {![json contains $paramsJson -key target -type string]} {
        jsonrpc throw \
                -code invalidParams \
                -message "Missing param target"
    }
    if {![json contains $paramsJson -key device -type string]} {
        jsonrpc throw \
                -code invalidParams \
                -message "Missing param device"
    }
    if {![json contains $paramsJson -key bitstream -type string]} {
        jsonrpc throw \
                -code invalidParams \
                -message "Missing param bitstream"
    }
    # Extract the base64 encoded bitstream from the request parameters and write
    # the decoded contents to a temporary file.
    set bitstreamBase64 [json get $paramsJson bitstream]
    set bitstreamBinary [::base64::decode $bitstreamBase64]
    set bitstreamFilePath [::fileutil::tempfile bitstream]
    file rename $bitstreamFilePath "$bitstreamFilePath.bit"
    set bitstreamFilePath "$bitstreamFilePath.bit"
    set bitstreamFileChan [open $bitstreamFilePath w]
    chan configure $bitstreamFileChan \
        -encoding binary \
        -translation binary
    chan puts -nonewline $bitstreamFileChan $bitstreamBinary
    chan close $bitstreamFileChan
    # Extract additional params
    set target [json get $paramsJson target]
    set device [json get $paramsJson device]
    # program the actual device
    vivado program $bitstreamFilePath $target $device
    # return json null
    return [json create null]
}

proc ::fpgaedu::vivadoserver::socketHandler {channelId} {
    variable rpcConfig
    catch {
        set requestData [chan read $channelId]
        set responseData [jsonrpc handle $rpcConfig $requestData]
        chan puts -nonewline $channelId $responseData
    }
    chan close $channelId
}

# http://wiki.tcl.tk/5947
proc ::fpgaedu::vivadoserver::acceptConnection {channelId addr port} {
    fconfigure $channelId -blocking 1 -buffering full
    fileevent $channelId readable [list ::fpgaedu::vivadoserver::socketHandler $channelId]
}

proc  ::fpgaedu::vivadoserver::Start {port} {
    # Registering an empty fileevent handler for stdin allows for the reading of 
    # SIGINT while the event loop is running.
    fileevent stdin readable {}
    puts "Starting server. Press Ctrl-C to exit"
    # Setup the socket connection handler and start the event loop.
    socket -server ::acceptConnection 12345
    vwait shutdown
}
