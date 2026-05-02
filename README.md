# Glint

Glint is a fast, native PostgreSQL database client for macOS. It is built entirely in Swift and uses PostgresNIO to connect directly to your databases. 

<video src="https://github.com/nosisky/Glint/raw/main/docs/glint-quick-demo.mp4" controls="controls" width="100%"></video>


## Features

* **Native macOS App:** Built for macOS 14 and later so it feels right at home on your Mac.
* **Multi-Tab Workspace:** Run and compare multiple database queries concurrently across separate tabs.
* **SSH Tunneling & SSL:** Secure your database connections with built-in SSH tunneling and strict SSL/TLS support.
* **Intelligent SQL Editor:** Features real-time SQL syntax highlighting and query formatting.
* **Fast Connections:** Uses PostgresNIO for quick and reliable database operations.
* **Smart Data Grid:** Easily view, search, and edit your database tables.
* **Deep Pagination for Custom SQL:** Execute complex raw SQL queries with seamless native pagination (Rows 1-200, 201-400), powered by intelligent under-the-hood CTE wrapping.
* **Universal Data Exporter:** Stream massive database tables and custom query results directly to disk as **CSV** or **JSON** arrays without freezing the app or causing Out-Of-Memory (OOM) crashes.
* **Safe Updates:** Uses Optimistic Concurrency Control to make sure you do not accidentally overwrite changes made by someone else.
* **Binary Data Handling:** Safely handles large binary files by showing small metadata summaries instead of locking up the UI.
* **JSON Editor:** A built-in popover tool to clearly read and edit JSON fields.
* **Keychain Security:** Database credentials and keys are securely stored in the native macOS Keychain.

## How to Build

You will need a Mac running macOS 14 or later and Swift 6 to build this project.

1. Clone the repository to your local computer.
2. Open the project in Xcode.
3. Build and run the `Glint` target.

## Author

Created by Nas (Nosisky).

## License

This project is released under a custom **Source-Available License**. 
You are free to view and read the source code for educational purposes. However, you are **not** permitted to modify, compile, distribute, or commercially exploit this software or its branding without explicit written permission. 

Please see the `LICENSE` file for full details.
