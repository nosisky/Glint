# Glint

Glint is a fast, native PostgreSQL database client for macOS. It is built entirely in Swift and uses PostgresNIO to connect directly to your databases. 

## Features

* **Native macOS App:** Built for macOS 14 and later so it feels right at home on your Mac.
* **Fast Connections:** Uses PostgresNIO for quick and reliable database operations.
* **Smart Data Grid:** Easily view, search, and edit your database tables.
* **Safe Updates:** Uses Optimistic Concurrency Control to make sure you do not accidentally overwrite changes made by someone else.
* **Binary Data Handling:** Safely handles large binary files by showing small metadata summaries instead of freezing the app.
* **JSON Editor:** A built in popover tool to clearly read and edit JSON fields.

## How to Build

You will need a Mac running macOS 14 or later and Swift 6 to build this project.

1. Clone the repository to your local computer.
2. Open the project in Xcode.
3. Build and run the `Glint` target.

## Author

Created by Nas (Nosisky).
