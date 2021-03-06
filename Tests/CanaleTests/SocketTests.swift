// Error.swift
//
// The MIT License (MIT)
//
// Copyright (c) 2016 Zewo
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import XCTest
import Venice
@testable import Canale

class SocketTests: XCTestCase {
    func testTimeout() throws {
        let context = try Context()
        let socket = try context.socket(.pull)
        try socket.setReceiveTimeout(100)
        try socket.setSendTimeout(100)
        try socket.bind("inproc://testTimeout")
        
        do {
            _ = try socket.receiveString()
            XCTFail()
        }
        catch {
            XCTAssertNotNil(error)
        }
    }
    
    func testPushPull() throws {
        var called = false
        let context = try Context()
        
        let outbound = try context.socket(.push)
        try outbound.connect("inproc://testPushPull")
        
        try outbound.send("Hello World!")
        try outbound.send("Bye!")

        let inbound = try context.socket(.pull)
        try inbound.bind("inproc://testPushPull")

        while let data = try inbound.receiveString() , data != "Bye!" {
            called = true
            XCTAssert(data == "Hello World!")
        }
        
        XCTAssert(called)
    }
    
    func testRouterDealer() throws {
        let numClients = 10
        
        let context = try Context()
        
        let serverGroup = Coroutine.Group()
        let server = try context.socket(.router)
        try server.bind("inproc://testRouterDealer")
        
        for _ in 0..<numClients {
            try serverGroup.addCoroutine {
                do {
                    let id = try server.receiveMessage(.ReceiveMore)
                    
                    let query = try server.receiveString()
                    
                    XCTAssertEqual(query, "How are you?")
                    
                    try server.send(id, mode: .SendMore)
                    try server.send("I am good")
                }
                catch {
                    XCTAssert(false)
                }
            }
        }
        
        let clientGroup = Coroutine.Group()
        let client = try context.socket(.dealer)
        try client.connect("inproc://testRouterDealer")
        var received = 0
        let completed = try Channel<Void>()
        
        for _ in 0..<numClients {
            try clientGroup.addCoroutine {
                do {
                    try! client.send("How are you?")
                    let reply = try client.receiveString()
                    XCTAssertEqual("I am good", reply)
                    
                    received += 1
                    
                    if received == numClients {
                        try completed.send(deadline: 1.second.fromNow())
                    }
                }
                catch {
                    XCTAssert(false)
                }
            }
        }
        
        try completed.receive(deadline: 10.second.fromNow())
        
    }
    
    
    func testRouterDealer1() throws {
        let numClients = 10
        
        let context = try Context()
        
        var received = 0
        let completed = try Channel<Void>()
        
        let client = try context.socket(.dealer)
        try client.connect("inproc://testRouterDealer1")
        let clientGroup = Coroutine.Group()
        
        for _ in 0..<numClients {
            try clientGroup.addCoroutine {
                do {
                    try! client.send("How are you?")
                    let reply = try client.receiveString()
                    XCTAssertEqual("I am good", reply)
                    
                    received += 1
                    
                    if received == numClients {
                        try completed.send(deadline: 1.second.fromNow())
                    }
                }
                catch {
                    XCTAssert(false)
                }
            }
        }
        
        let server = try context.socket(.router)
        try server.bind("inproc://testRouterDealer1")

        for _ in 0..<numClients {
            do {
                let id = try server.receiveMessage(.ReceiveMore)
                
                let query = try server.receiveString()
                
                XCTAssertEqual(query, "How are you?")
                
                try server.send(id, mode: .SendMore)
                try server.send("I am good")
            }
            catch {
                XCTAssert(false)
            }
        }
        
        try completed.receive(deadline: 10.second.fromNow())
    }

    
    func testReqRep() throws {
        let numClients = 10
        
        var context: Context! = try Context()
        
        let completed = try Channel<Void>()
        
        var rep: Socket! = try context.socket(.rep)
        try rep.bind("inproc://testReqRep")
        let group = Coroutine.Group()
        
        try group.addCoroutine {
            for _ in 0..<numClients {
                do {
                    let query = try rep.receiveString()
                    XCTAssertEqual(query, "Hi!")
                    try rep.send("Bye!")
                }
                catch {
                    XCTAssert(false)
                }
            }
        }
        
        
        var received = 0
        var req: Socket! = try context.socket(.req)
        try req.connect("inproc://testReqRep")

        try group.addCoroutine {
            for _ in 0..<numClients {
                try Coroutine.wakeUp(1.millisecond.fromNow())
                do {
                    try req.send("Hi!")
                    let query = try req.receiveString()
                    XCTAssertEqual(query, "Bye!")
                    
                    received += 1
                    
                    if numClients == received {
                        try completed.send(deadline: 1.second.fromNow())
                    }
                }
                catch {
                    XCTAssert(false)
                }
            }
        }
        
        
        try completed.receive(deadline: (numClients + 1).second.fromNow())

        //TODO: need to release sockets before context, otherwise zmq_ctx_term might hang
        req = nil
        rep = nil
        context = nil
    }

}

extension SocketTests {
    static var allTests: [(String, (SocketTests) -> () throws -> Void)] {
        return [
            ("testPushPull", testPushPull), ("testRouterDealer", testRouterDealer), ("testRouterDealer1", testRouterDealer1), ("testReqRep", testReqRep)
        ]
    }
}
