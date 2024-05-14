//
//  TestUtils.swift
//  CountlyTests
//
//  Created by Arif Burak Demiray on 13.05.2024.
//  Copyright © 2024 Countly. All rights reserved.
//

import Foundation
import XCTest


class TestUtils{
    
    static var kCountlyPersistencyFileName = "Countly.dat"
    
    static var kCountlyQueuedRequestsPersistencyKey = "kCountlyQueuedRequestsPersistencyKey";

    // this function is not working as expected
    // todo work on this
    static func getCurrentRQ() -> [NSDictionary] {
        let requests: [NSDictionary] = [NSDictionary]()
        do {
            let path = try storageFileURL()?.absoluteString
            let readData = try NSData(contentsOfFile: path! + "" ,options: NSData.ReadingOptions.alwaysMapped)

            // MARK: GCC diagnostic push
            // MARK: GCC diagnostic ignored "-Wdeprecated-declarations"
            let readDict: NSDictionary? = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSDictionary.self, from: readData as Data)
            // MARK: GCC diagnostic pop
            if(readDict == nil){
                return requests
            }
            let queue = readDict![kCountlyQueuedRequestsPersistencyKey]
            
            return queue! as! [NSDictionary]
        } catch {
            // do nothing
        }
       
        
        return requests

    }
    
    static func storageFileURL() throws -> URL?
    {
        return try storageDirectoryURL().appendingPathComponent(kCountlyPersistencyFileName);
    }
    
    static func storageDirectoryURL() throws -> URL
    {
        let URL: URL
        let directory: FileManager.SearchPathDirectory

    #if (TARGET_OS_TV)
        directory = FileManager.SearchPathDirectory.cachesDirectory
    #else
        directory = FileManager.SearchPathDirectory.applicationSupportDirectory
    #endif
        URL = FileManager.default.urls(for: directory, in:.userDomainMask).first!


    #if (TARGET_OS_OSX)
        URL = URL.appending(path: NSBundle.main.bundleIdentifier)
    #endif
        if(!FileManager.default.fileExists(atPath: URL.path)){
             try FileManager.default.createDirectory(at: URL, withIntermediateDirectories: true)
        }

        return URL;
    }
    
    static func saveStorage(requests: [NSDictionary]){
        // MARK: GCC diagnostic push
        // MARK: GCC diagnostic ignored "-Wdeprecated-declarations"
        do{
            let saveData: NSData = try NSKeyedArchiver.archivedData(withRootObject: [kCountlyQueuedRequestsPersistencyKey: requests], requiringSecureCoding: false) as NSData
            let path = try storageFileURL()?.absoluteString
            try saveData.write(toFile: path!)
        } catch {
            // do nothing
        }
        // MARK: GCC diagnostic pop
    }
}
