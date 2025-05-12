package store

import (
    "database/sql"
    "fmt"
    _ "github.com/lib/pq"
)

type DB struct {
    *sql.DB
}

func NewDB(dsn string) *DB {
    db, err := sql.Open("postgres", dsn)
    if err != nil {
        panic(err)
    }
    if err := db.Ping(); err != nil {
        panic(err)
    }
    fmt.Println("✅ Connected to Postgres")
    return &DB{db}
}