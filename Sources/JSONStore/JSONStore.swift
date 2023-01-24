public class JSONEntity {
    private var jsonText: String
    private var arrayValues:[(value: String, type: String)] = []
    private var objectEntries:[(key: String, value: String, type: String)] = []
    private var contentType:String
    private var copyArrayData:Bool = false
    private var copyObjectEntries:Bool = false
    
    public enum JSONType: String {
        case string = "string"
        case boolean = "boolean"
        case object = "object"
        case array = "array"
        case number = "number"
        case null = "null"
        
        init(_ v: String) {
            self = .init(rawValue: v)!
        }
    }
    
    public enum SerializationType {
        case simple
        case nested
    }
        
    public init(_ json:String) {
        jsonText = json
        switch (jsonText.first) {
            case "{": contentType = "object"
            case "[": contentType = "array"
            default: contentType = "string"
        }
    }
    
    private init(_ json: String, _ type: String) {
        jsonText = json
        contentType = type
    }
    
    private func getField <T>(_ path: String?, _ fieldName: String, _ mapper: (String) -> T?, ignoreType:Bool = false) -> T? {
        guard let (data, type) = path == nil ? (jsonText, contentType) : decodeData(path!) else { return nil; }
        if !ignoreType && type != fieldName { return nil }
        return mapper(data)
    }
    
    public func string(_ path:String? = nil) -> String? {
        return getField(path, "string", { $0 })
    }
    
    public func number(_ path:String? = nil, ignoreType: Bool = false) -> Double? {
        return getField(path, "number", { Double($0) }, ignoreType: ignoreType)
    }
    
    public func isNull(_ path:String? = nil) -> Bool? {
        guard let type = path == nil ? contentType: decodeData(path!)?.type else {
            return nil
        }
        return type == "null"
    }
    
    public func object(_ path:String? = nil) -> JSONEntity? {
        if path == nil { return self }
        return getField(path, "object", { JSONEntity($0, "object")})
    }
    
    public func bool(_ path: String? = nil, ignoreType: Bool = false) -> Bool? {
        return getField(path, "boolean", { $0 == "true" }, ignoreType: ignoreType)
    }
    
    public func array(_ path:String? = nil) -> [JSONEntity]? {
        copyArrayData = true
        let data = decodeData(path == nil ? "-1" : "\(path!).-1")
        if data?.value != "$COMPLETE_ARRAY" || data?.type != "code" {
            copyArrayData = false
            return nil
        }
        let results = arrayValues.map({value in
            return JSONEntity(value.value, value.type)
        }) as [JSONEntity]
        copyArrayData = false
        return results
    }
    
    public func isExist(_ path:String) -> Bool {
        return decodeData(path) != nil
    }
    
    public func entries(_ path:String) -> [(key: String, value: JSONEntity)]? {
        copyObjectEntries = true
        let data = decodeData(path.count == 0 ? "dummyAtr" : "\(path).dummyAtr")
        if data?.value != "$COMPLETE_OBJECT" || data?.type != "code" {
            copyObjectEntries = false
            return nil
        }
        let results = objectEntries.map({ value in
            return (value.key, JSONEntity(value.value, value.type))
        }) as [(String, JSONEntity)]
        copyObjectEntries = false
        return results
    }

    private func resolveValue(value: String, type: String, serialization: SerializationType? = nil) -> Any? {
        switch(type) {
            case "number": return Double(value)!
        case "object":
            if serialization == .none {
                return JSONEntity(value, "object")
            }
            if serialization == .simple {
                return value
            }
            
            var objData: [String: Any?] = [String: Any?]()
            JSONEntity(value, type).entries("")!.forEach({
                key, nestedValue in objData[key] = resolveValue(value: nestedValue.jsonText, type: nestedValue.contentType, serialization: serialization)
            })
            return objData
            
        case "array":
            if serialization == .none {
                return JSONEntity(value, "array").array()!
            }
            if serialization == .simple {
                return value
            }
            return JSONEntity(value).array()!
                .map({ item in
                    return resolveValue(value: item.jsonText, type: item.contentType, serialization: serialization)
                }) as [Any?]
            
            case "boolean": return value == "true" ? true : false
            case "null": return nil
            default: return value
        }
    }
    
    public func value(_ path: String? = nil) -> (value: Any?, type: JSONType)? {
        guard let (value, type) = (path == nil ? (jsonText, contentType) : decodeData(path!)) else { return nil }
        return (resolveValue(value: value, type: type), JSONType(type))
    }
    
    public func type() -> JSONType {
        return JSONType(contentType)
    }
    
    public func dump(_ path: String? = nil) -> String? {
        return path == nil ? jsonText : decodeData(path!)?.value
    }
    
    public func serialize(_ serializeMode: SerializationType) -> Any? {
        return resolveValue(value: jsonText, type: contentType, serialization: serializeMode)
    }
    
    public func serialize(_ path: String, _ serializeMode: SerializationType) -> Any? {
        guard let (value, type) = decodeData(path) else { return nil }
        return resolveValue(value: value, type: type, serialization: serializeMode)
    }
    
    public func capture(_ path: String) -> JSONEntity? {
        guard let result = decodeData(path) else { return nil }
        return JSONEntity(result.value, result.type)
    }
            
    private func decodeData(_ inputPath:String) -> (value: String, type: String)? {
        let paths = inputPath.split(separator: ".")
        var processedPathIndex = 0

        var isInQuotes = false
        var startSearchValue = false
        var isGrabbingText = false
        var grabbedText = ""
        var grabbingKey = ""
        var isGrabbingNotation = false
        var isGrabbingKey = false
        var isCountArray = false
        var isGrabbingMultipleValues = false
        
        var elementIndexCursor = -1 // the count variable when iterating array
        var pathArrayIndex = -1 // the array index of given on path
        var notationBalance = 0
        var grabbingDataType: String = "string"
        var possibleType: String = ""
        
        arrayValues = []
        objectEntries = []
        
        for char in jsonText {
            // if within quotation ignore processing json literals...
            if !isInQuotes {
                if char == "{" || char == "[" {
                    notationBalance += 1
                    
                    if isCountArray {
                        // ignore processing if element in not matching the array index
                        if elementIndexCursor != pathArrayIndex {
                            if isGrabbingMultipleValues {
                                if notationBalance == processedPathIndex + 2 {
                                    grabbingDataType = char == "{" ? "object" : "array"
                                }
                                grabbedText.append(char)
                            }
                            continue
                        }
                        processedPathIndex += 1
                        isCountArray = false
                    }
                    // if the last value of last key is object or array then start copy it
                    if processedPathIndex == paths.count && !isGrabbingNotation {
                        grabbedText = ""
                        isGrabbingNotation = true
                        grabbingDataType = char == "{" ? "object" : "array"
                    }
                    // continue copying object/arrray notation...
                    if isGrabbingNotation {
                        grabbedText.append(char)
                        continue
                    }
                    
                    // starting to count elements in array on reaching open bracket...
                    if char == "[" && !isCountArray && (processedPathIndex + 1) == notationBalance {
                        let parsedIndex = Int(paths[processedPathIndex])
                        // occur when trying to access element of array with non-number index
                        if parsedIndex == nil {
                            return nil
                        }
                        isCountArray = true
                        pathArrayIndex = parsedIndex!
                        elementIndexCursor = 0
                        startSearchValue = true
                        // start to copy all element in array on last -1 index
                        if copyArrayData && (processedPathIndex + 1) == paths.count {
                            isGrabbingMultipleValues = true
                        }
                    } else {
                        // upon meeting open 'notation' searching for next key on next path should start
                        startSearchValue = false
                    }
                    
                    continue
                }
                
                if char == "}" || char == "]" {
                    notationBalance -= 1
                    
                    // if a primitive value is in proccess copying then return copied value
                    if isGrabbingText {
                        // when finished copy last primitive value on copyObjectEntries mode. Need to make sure the parent container notation is an object
                        if copyObjectEntries && char == "}" {
                            objectEntries.append((grabbingKey, grabbedText, grabbingDataType))
                            return ("$COMPLETE_OBJECT", "code")
                        }
                        return (grabbedText, grabbingDataType)
                    }
                    if isGrabbingNotation { grabbedText.append(char) }
                    
                    // occur after all element in foccused array or object is finished searching...
                    if notationBalance == processedPathIndex {
                        if isCountArray {
                            // occur when when not matching element is found for given array index and array finished iterating...
                            if isGrabbingMultipleValues {
                                arrayValues.append((grabbedText, grabbingDataType))
                                return ("$COMPLETE_ARRAY", "code")
                            }
                            return nil
                        }
                        // exit occur after no matching key is found in object
                        if char == "}" && !startSearchValue {
                            if copyObjectEntries { return ("$COMPLETE_OBJECT", "code") }
                            return nil
                        }
                        
                        // occur after finishing copy json notation
                        if processedPathIndex == paths.count {
                            if !copyObjectEntries { return (grabbedText, grabbingDataType) }
                            objectEntries.append((grabbingKey, grabbedText , grabbingDataType))
                            startSearchValue = false
                            isGrabbingNotation = false
                            processedPathIndex -= 1
                        }
                    }
                    if isGrabbingMultipleValues { grabbedText.append(char) }
                    continue
                }
                if isGrabbingNotation {
                    grabbedText.append(char)
                    continue
                }
            }
            
            // isGrabbingMultipleValues is flag to capture all elements in array
            if isGrabbingMultipleValues {
                // after each element in array level there would be ',' character
                if char == "," && (processedPathIndex + 1) == notationBalance {
                    arrayValues.append((grabbedText, grabbingDataType))
                    grabbedText = ""
                    continue
                } else {
                    grabbedText.append(char)
                }
            }
            
            if startSearchValue {
                if notationBalance == processedPathIndex || (isCountArray && (processedPathIndex + 1) == notationBalance) {
                    
                    if char == "\"" {
                        isInQuotes = !isInQuotes
                        if isCountArray && elementIndexCursor != pathArrayIndex {
                            if isInQuotes {
                                grabbingDataType = "string"
                            }
                            continue
                        }
                        isGrabbingText = !isGrabbingText
                        if !isGrabbingText {
                            if !copyObjectEntries { return (grabbedText, "string") }
                            objectEntries.append((grabbingKey, grabbedText, "string"))
                            startSearchValue = false
                            processedPathIndex -= 1
                        } else {
                            grabbingDataType = "string"
                            grabbedText = ""
                        }
                        // used to copy values true, false, null and number
                    } else {
                        possibleType = ""
                        
                        if char.isNumber || char == "-" { possibleType = "number" }
                        else if char == "t" || char == "f" { possibleType = "boolean" }
                        else if char == "n" { possibleType = "null" }
                        
                        if !isInQuotes && !isGrabbingText && possibleType != "" {
                            grabbingDataType = possibleType
                            if isCountArray && elementIndexCursor != pathArrayIndex { continue }
                            grabbedText = ""
                            grabbedText.append(char)
                            isGrabbingText = true
                            continue
                        } else if !isInQuotes && char == "," {
                            if isCountArray {
                                elementIndexCursor += 1
                                continue
                            }
                            if isGrabbingText {
                                if copyObjectEntries {
                                    objectEntries.append((grabbingKey, grabbedText, grabbingDataType))
                                    startSearchValue = false
                                    isGrabbingText = false
                                    processedPathIndex -= 1
                                } else  {
                                    return (grabbedText, grabbingDataType)
                                }
                            }
                        } else if isGrabbingText {
                            grabbedText.append(char)
                        }
                    }
                }
                // section responsible for finding matching key in object notation
            } else {
                // grabbing the matching correct object key as given in path
                if (processedPathIndex + 1) == notationBalance && char == "\"" {
                    isGrabbingKey = !isGrabbingKey
                    isInQuotes = !isInQuotes
                    if !isGrabbingKey {
                        // if found start searching for object value for object key
                        if (copyObjectEntries && (processedPathIndex + 1) == paths.count) || grabbingKey == paths[processedPathIndex] {
                            processedPathIndex += 1
                            startSearchValue = true
                        }
                    } else {
                        grabbingKey = ""
                    }
                } else if isGrabbingKey {
                    grabbingKey.append(char)
                }
            }
        }
        return nil
    }
}
