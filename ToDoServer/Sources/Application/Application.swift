import Foundation
import Kitura
import LoggerAPI
import Configuration
import CloudEnvironment
import KituraContracts
import Health
import KituraOpenAPI
import KituraCORS
import Dispatch
import SwiftKueryORM
import SwiftKueryPostgreSQL

public let projectPath = ConfigurationManager.BasePath.project.path
public let health = Health()

public class App {
    let router = Router()
    let cloudEnv = CloudEnv()
	private var nextId: Int = 0
	private let workerQueue = DispatchQueue(label: "worker")
	
    public init() throws {
        // Run the metrics initializer
        initializeMetrics(router: router)
		
    }

    func postInit() throws {
        // Endpoints
        initializeHealthRoutes(app: self)
		KituraOpenAPI.addEndpoints(to: router)
		let options = Options(allowedOrigin: .all)
		let cors = CORS(options: options)
		router.all("/*", middleware: cors)
		router.post("/", handler: storeHandler)
		router.delete("/", handler: deleteAllHandler)
		router.get("/", handler: getAllHandler)
		router.get("/", handler: getOneHandler)
		router.patch("/", handler: updateHandler)
		router.delete("/", handler: deleteOneHandler)
		
		
		Persistence.setUp()
		do {
			try ToDo.createTableSync()
		} catch let error {
			print(error)
		}

	}

    public func run() throws {
        try postInit()
        Kitura.addHTTPServer(onPort: cloudEnv.port, with: router)
        Kitura.run()
    }
	
	func execute(_ block: (() -> Void)) {
		workerQueue.sync {
			block()
		}
	}
	
	func storeHandler(todo: ToDo, completion: @escaping (ToDo?, RequestError?) -> Void ) {
		var todo = todo
		if todo.completed == nil {
			todo.completed = false
		}
		todo.id = nextId
		todo.url = "http://localhost:8080/\(nextId)"
		nextId += 1
		todo.save(completion)
		
	}
	
	func deleteAllHandler(completion: @escaping (RequestError?) -> Void ) {
		ToDo.deleteAll(completion)
	}
	
	func getAllHandler(completion: @escaping ([ToDo]?, RequestError?) -> Void ) {
		ToDo.findAll(completion)
	}
	
	func getOneHandler(id: Int, completion: @escaping(ToDo?, RequestError?) -> Void ) {
		ToDo.find(id: id, completion)
	}
	
	func updateHandler(id: Int, new: ToDo, completion: @escaping (ToDo?, RequestError?) -> Void ) {

		ToDo.find(id: id) { (preExistingToDo, error) in
			if let error = error {
				
			}
			
			guard var oldToDo = preExistingToDo else {
				print("Unable to find ToDo in database.")
				return
			}
			
			oldToDo.user = new.user ?? oldToDo.user
			oldToDo.order = new.order ?? oldToDo.order
			oldToDo.title = new.title ?? oldToDo.title
			oldToDo.completed = new.completed ?? oldToDo.completed
			
			oldToDo.update(id: oldToDo.id!, completion)
			
		}
	}
	
	func deleteOneHandler(id: Int, completion: @escaping (RequestError?) -> Void ) {
		ToDo.delete(id: id, completion)

	}
}

class Persistence {
	static func setUp() {
		let pool = PostgreSQLConnection.createPool(host: "localhost", port: 5432, options: [.databaseName("tododb")], poolOptions: ConnectionPoolOptions(initialCapacity: 10, maxCapacity: 50, timeout: 10000))
		Database.default = Database(pool)
	}
}
