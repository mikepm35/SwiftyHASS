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

public class SwiftyHASS {
    
    // MARK: Properties
    
    // Initialization properties
    
    public var httpsecure: Bool
    public var ipaddr_inhome: String
    public var ipaddr_ooh: String
    public var portnum: String
    public var api_password: String
    public var baseurl_inhome: String
    public var baseurl_ooh: String
    public var headers: HTTPHeaders = [:]
    public var config_loaded: Bool
    
    // Entity properties
    
    public var switches: [Switch]
    
    
    // MARK: Initialization
    
    // Attempt to initialize with stored values
    
    public init() {
        let local_data = ConfigStore.LoadData()
        
        var httpsecure = false
        var ipaddr_inhome = "empty"
        var ipaddr_ooh = "empty"
        var portnum = "empty"
        var api_password = "empty"
        var config_loaded = true
        
        if let data = local_data?[0].httpsecure {
            httpsecure = data
        } else {
            config_loaded = false
        }
        
        if let data = local_data?[0].ipaddr_inhome {
            ipaddr_inhome = data
        } else {
            config_loaded = false
        }
        
        if let data = local_data?[0].ipaddr_ooh {
            ipaddr_ooh = data
        } else {
            config_loaded = false
        }
        
        if let data = local_data?[0].portnum {
            portnum = data
        } else {
            config_loaded = false
        }
        
        if let data = local_data?[0].api_password {
            api_password = data
        } else {
            config_loaded = false
        }
        
        self.httpsecure = httpsecure
        self.ipaddr_inhome = ipaddr_inhome
        self.ipaddr_ooh = ipaddr_ooh
        self.portnum = portnum
        self.api_password = api_password
        self.config_loaded = config_loaded
        
        
        // Setup base urls and header
        
        self.baseurl_ooh = createBaseUrl(secure: httpsecure, ipaddr: ipaddr_ooh, portnum: portnum)
        self.baseurl_inhome = createBaseUrl(secure: httpsecure, ipaddr: ipaddr_inhome, portnum: portnum)
        
        self.headers["x-ha-access"] = api_password
        self.headers["content-type"] = "application/json"
        
        
        // Initialize entities as empty
        
        self.switches = [Switch]()
        
    }
    
    
    // Initialize with new configuration
    
    public init(httpsecure: Bool, ipaddr_inhome: String, ipaddr_ooh: String, portnum: String, api_password: String) {
        self.httpsecure = httpsecure
        self.ipaddr_inhome = ipaddr_inhome
        self.ipaddr_ooh = ipaddr_ooh
        self.portnum = portnum
        self.api_password = api_password
        self.config_loaded = true
        
        
        // Setup base urls and header
        
        self.baseurl_ooh = createBaseUrl(secure: self.httpsecure, ipaddr: self.ipaddr_ooh, portnum: self.portnum)
        self.baseurl_inhome = createBaseUrl(secure: self.httpsecure, ipaddr: self.ipaddr_inhome, portnum: self.portnum)
        
        self.headers["x-ha-access"] = self.api_password
        self.headers["content-type"] = "application/json"
        
        
        // Initialize entities as empty
        
        self.switches = [Switch]()
        
        
        // Load configuration to stored data
        
        let new_configstore = ConfigStore(httpsecure: httpsecure, ipaddr_inhome: ipaddr_inhome, ipaddr_ooh: ipaddr_ooh, portnum: portnum, api_password: api_password)
        
        ConfigStore.SaveData(configstore: [new_configstore!])
        
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
            if let JSON = response.result.value as? [Any] {
                for object in JSON {
                    if let state_object = object as? [String:Any] {
                        if let switch_holder = Switch(json: state_object) {
                            _ = self.deleteOldMatchingSwitch(api_name: switch_holder.api_name)
                            self.switches += [switch_holder]
                            switch_count += 1
                            print("HA entity is a switch, adding: \(switch_holder.api_name)")
                        } else {
                            print("HA entity is not a switch, skipping")
                        }
                    }
                }
            } else {
                print("ERROR casting HA states response")
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
            print("ERROR due to switch index not matching")
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
            print("ERROR due to unsupported switch setting")
            state_endpoint = "/error"
        }
        
        let endpoint = "/api/services/switch" + state_endpoint
        let baseurl = checkIP()
        let fullurl = baseurl + endpoint
        
        // TODO: Add switch details to headers
        
        let parameters = ["entity_id": entity_id_requested]
        
        Alamofire.request(fullurl, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: headers).validate().responseJSON { response in
            
            var response_string: String
            switch response.result {
            case .success:
                response_string = "SUCCESS"
            case .failure(let error):
                print("ERROR validating set switch response")
                response_string = "FAILURE"
            }
            
            resultHandler(response_string)
        }
    }
    
    
    // MARK: Utility functions
    
    public func checkIP() -> String {
        /*
         In some cases the Home Assistant may be NAT'd behind a router. Check if the In Home address is reachable, otherwise default to Out of Home (OOH). Request failiures (including if neither address is reachable) are handled by the individual request functions.
         */
        
        let baseip_inhome = createBaseUrl(secure: httpsecure, ipaddr: ipaddr_inhome, portnum: portnum)
        
        let reach_manager = NetworkReachabilityManager(host: baseip_inhome)
        let reach_result = reach_manager?.isReachable
        
        print(reach_result)
        if reach_result! {
            return baseurl_inhome
        } else {
            print("In Home reachability check failed, setting default to OOH")
            return baseurl_ooh
        }
        
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
        
        print("No match for switch friendly name")
        return -1
        
    }
    
}

public struct Switch {
    public var entity_id: String
    public var last_updated: String
    public var state: String
    public var friendly_name: String
    public var api_name: String
    
    public init(entity_id: String, last_updated: String, state: String, friendly_name: String, api_name: String) {
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
                print("ERROR in unwrapping entity_id")
                return nil
        }
        
        let (testSwitch, api_name) = isEntityDomainSwitch(entity_id: entity_id)
        
        if testSwitch {
            guard let last_updated = json["last_updated"] as? String,
                let state = json["state"] as? String,
                let attributes = json["attributes"] as? [String: String],
                let friendly_name = attributes["friendly_name"]
                else {
                    print("ERROR unwrapping switch attributes")
                    return nil
            }
            
            self.entity_id = entity_id
            self.last_updated = last_updated
            self.state = state
            self.friendly_name = friendly_name
            self.api_name = api_name
            
        } else {
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

private func createBaseUrl(with_port: Bool = true, secure: Bool, ipaddr: String, portnum: String) -> (String) {
    var httpstring = "https"
    if !secure {
        httpstring = "http"
    }
    
    var baseurl = httpstring + "://" + ipaddr
    if with_port {
        baseurl = baseurl + ":" + portnum
    }
    
    return baseurl
}




// MARK: Local storage

struct PropertyKey {
    static let httpsecure_key = "httpsecure"
    static let ipaddr_inhome_key = "ipaddr_inhome"
    static let ipaddr_ooh_key = "ipaddr_ooh"
    static let portnum_key = "portnum"
    static let api_password_key = "api_password"
}

class ConfigStore: NSObject, NSCoding {
    
    // Properties
    
    var httpsecure: Bool
    var ipaddr_inhome: String
    var ipaddr_ooh: String
    var portnum: String
    var api_password: String
    
    
    // Archiving Paths
    
    static let DocumentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    
    static let ArchiveURL = DocumentsDirectory.appendingPathComponent("configstore")
    
    
    // Initialization
    
    init?(httpsecure: Bool, ipaddr_inhome: String, ipaddr_ooh: String, portnum: String, api_password: String) {
        self.httpsecure = httpsecure
        self.ipaddr_inhome = ipaddr_inhome
        self.ipaddr_ooh = ipaddr_ooh
        self.portnum = portnum
        self.api_password = api_password
        
        super.init()
    }
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(httpsecure, forKey: PropertyKey.httpsecure_key)
        aCoder.encode(ipaddr_inhome, forKey: PropertyKey.ipaddr_inhome_key)
        aCoder.encode(ipaddr_ooh, forKey: PropertyKey.ipaddr_ooh_key)
        aCoder.encode(portnum, forKey: PropertyKey.portnum_key)
        aCoder.encode(api_password, forKey: PropertyKey.api_password_key)
    }
    
    required convenience init?(coder aDecoder: NSCoder) {
        let httpsecure = aDecoder.decodeBool(forKey: PropertyKey.httpsecure_key)
        let ipaddr_inhome = aDecoder.decodeObject(forKey: PropertyKey.ipaddr_inhome_key) as! String
        let ipaddr_ooh = aDecoder.decodeObject(forKey: PropertyKey.ipaddr_ooh_key) as! String
        let portnum = aDecoder.decodeObject(forKey: PropertyKey.portnum_key) as! String
        let api_password = aDecoder.decodeObject(forKey: PropertyKey.api_password_key) as! String
        
        self.init(httpsecure: httpsecure, ipaddr_inhome: ipaddr_inhome, ipaddr_ooh: ipaddr_ooh, portnum: portnum, api_password: api_password)
    }
    
    
    // NSCoding
    
    class func SaveData(configstore: [ConfigStore]) {
        let is_successful_save = NSKeyedArchiver.archiveRootObject(configstore, toFile: ConfigStore.ArchiveURL.path)
        
        if !is_successful_save {
            print("ERROR in saving configuration locally")
        }
    }
    
    class func LoadData() -> [ConfigStore]? {
        return NSKeyedUnarchiver.unarchiveObject(withFile: ConfigStore.ArchiveURL.path) as? [ConfigStore]
    }
}


