import Foundation
import PostgresNIO

func test(cell: PostgresCell) {
    let t = cell.dataType
    print(t == .int4)
    print(t == .text)
}
