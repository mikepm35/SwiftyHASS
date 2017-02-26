//
//  swiftha.swift
//  siriha
//
//  Created by Moritz, Michael on 1/14/17.
//  Copyright © 2017 mpmoritz. All rights reserved.
//

import Foundation
import Alamofire

public enum switchStates: String {
    case on = "on"
    case off = "off"
}

public class Swiftha {
    
    // MARK: Properties
    
    // Initialization properties
    var httpsecure: Bool
    var ipaddr_inhome: String
    var ipaddr_ooh: String
    var portnum: String
    var api_password: String
    var baseurl_inhome: String
    var baseurl_ooh: String
    var headers: HTTPHeaders = [:]
    
    // Entity properties
    var switches: [Switch]
    
    
    // MARK: Initialization
    
    public init(httpsecure: Bool, ipaddr_inhome: String, ipaddr_ooh: String, portnum: String, api_password: String) {
        self.httpsecure = httpsecure
        self.ipaddr_inhome = ipaddr_inhome
        self.ipaddr_ooh = ipaddr_ooh
        self.portnum = portnum
        self.api_password = api_password
        
        
        // Setup base urls
        
        var httpstring = "https"
        if self.httpsecure == false {
            httpstring = "http"
        }
        
        self.baseurl_ooh = httpstring + "://" + self.ipaddr_ooh + ":" + self.portnum
        self.baseurl_inhome = httpstring + "://" + self.ipaddr_inhome + ":" + self.portnum
        
        
        // Setup header
        
        headers["x-ha-access"] = self.api_password
        headers["content-type"] = "application/json"
        
        
        // Initialize entities as empty
        
        switches = [Switch]()
        
    }
    
    
    // MARK: Home Assistant API Wrapper
    
    // For more detail: https://home-assistant.io/developers/rest_api/
    
    public func loadSwitches(resultHandler: @escaping (_ switchesFound: Int) -> ()) -> () {
        /*
         Adds array of state objects to class with following attributes: entity_id, state, last_changed, and attributes
         Returns number of switches found
         */
        
        let endpoint = "/api/states"
        let baseurl = checkIP()
        let fullurl = baseurl + endpoint
        var switch_count = 0
        
        Alamofire.request(fullurl, headers: headers).validate().responseJSON { response in
            print(response.request ?? "")  // original URL request
            print(response.response ?? "") // HTTP URL response
            print(response.data ?? "")     // server data
            print(response.result)   // result of response serialization
            
            switch response.result {
            case .success:
                print("Validation Successful")
            case .failure(let error):
                print(error)
            }
            
            if let JSON = response.result.value as? [Any] {
                print("JSON: \(JSON)")
                for object in JSON {
                    print("Running object for loop")
                    if let state_object = object as? [String:Any] {
                        if let switch_holder = Switch(json: state_object) {
                            _ = self.deleteOldMatchingSwitch(api_name: switch_holder.api_name)
                            self.switches += [switch_holder]
                            switch_count += 1
                            print("Switch length: \(self.switches.count)")
                        } else {
                            print("Switch returned nil")
                        }
                    }
                }
            } else {
                print("cast error")
            }
            
            resultHandler(switch_count)
        }
    }

    
    public func setSwitchByFriendly(switch_friendly_name: String, state_requested: switchStates, resultHandler: @escaping (_ responseObject: String) -> ()) -> () {
        /*
         Takes in a switch friendly and switchState, finds the switch object, and posts to Home Assistant
         Returns SUCCESS or FAILURE based on HTTP status code and response validation
         */
        
        let switch_index = getSwitchIndexForFriendly(friendly_name: switch_friendly_name)
        
        var entity_id_requested = ""
        if switch_index < 0 {
            print("return false, switch index did not match")
            entity_id_requested = "ERROR"
        } else {
            entity_id_requested = switches[switch_index].entity_id
        }
        
        var state_endpoint = ""
        if state_requested == switchStates.on {
            state_endpoint = "/turn_on"
        } else if state_requested == switchStates.off{
            state_endpoint = "/turn_off"
        } else {
            print("error")
            state_endpoint = "/error"
        }
        
        let endpoint = "/api/services/switch" + state_endpoint
        let baseurl = checkIP()
        let fullurl = baseurl + endpoint
        
        // TODO: Add switch details to headers
        
        let parameters = ["entity_id": entity_id_requested]
        
        Alamofire.request(fullurl, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: headers).validate().responseJSON { response in
            print(response.request ?? "")  // original URL request
            print(response.response ?? "") // HTTP URL response
            print(response.data ?? "")     // server data
            print(response.result)   // result of response serialization
            
            var response_string: String
            switch response.result {
            case .success:
                print("Validation Successful")
                response_string = "SUCCESS"
            case .failure(let error):
                print(error)
                response_string = "FAILURE"
            }
            
            resultHandler(response_string)
        }
    }
    
    
    // MARK: Utility functions
    
    public func checkIP() -> String {
        //TODO: do a ping to determine in-home vs out-of-home
        return baseurl_inhome
    }
    
    public func deleteOldMatchingSwitch(api_name: String) -> Bool {
        var switch_index = 0
        var switch_match = -1
        
        for s in switches {
            if s.api_name == api_name {
                switch_match = switch_index
            }
            switch_index += 1
        }
        
        if switch_match > 0 {
            print("Removing old duplicate switch")
            switches.remove(at: switch_match)
            return true
        } else {
            return false
        }
        
    }
    
    public func getSwitchIndexForFriendly(friendly_name: String) -> Int {
        var switch_index = 0
        
        for s in switches {
            if s.friendly_name == friendly_name {
                return switch_index
            }
            switch_index += 1
        }
        
        print("No match for friendly name")
        return -1
        
    }
    
}

public struct Switch {
    var entity_id: String
    var last_updated: String
    var state: String
    var friendly_name: String
    var api_name: String
    
    init(entity_id: String, last_updated: String, state: String, friendly_name: String, api_name: String) {
        self.entity_id = entity_id
        self.last_updated = last_updated
        self.state = state
        self.friendly_name = friendly_name
        self.api_name = api_name
    }
}


public extension Switch {
    init?(json: [String: Any]) {
        guard let entity_id = json["entity_id"] as? String
            else {
                print("Failed unwrapping entity_id")
                return nil
        }
        
        let (testSwitch, api_name) = isEntityDomainSwitch(entity_id: entity_id)
        
        if testSwitch {
            
            print(api_name)
            
            guard let last_updated = json["last_updated"] as? String,
                let state = json["state"] as? String,
                let attributes = json["attributes"] as? [String: String],
                let friendly_name = attributes["friendly_name"]
                else {
                    print("Failed unwrapping switch attributes")
                    return nil
            }
            
            self.entity_id = entity_id
            self.last_updated = last_updated
            self.state = state
            self.friendly_name = friendly_name
            self.api_name = api_name
            
        } else {
            
            print("Not a test switch")
            return nil
            
        }
        
    }
}


// MARK: General utility functions

private func isEntityDomainSwitch(entity_id: String) -> (Bool, String) {
    /*
     Takes in an string formated as domain.entity
     Returns true if domain is "switch" and false otherwise
     */
    
    let index_to = entity_id.index(entity_id.startIndex, offsetBy: 6)
    let test_domain = entity_id.substring(to: index_to)
    
    if test_domain == "switch" {
        let index_from = entity_id.index(entity_id.startIndex, offsetBy: 7)
        let api_name = entity_id.substring(from: index_from)
        return (true, api_name)
    } else {
        return (false, "")
    }
    
}

