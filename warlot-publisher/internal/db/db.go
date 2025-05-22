// internal/db/db.go
package db

import (
  "database/sql"
  "fmt"
  "os"

  _ "github.com/lib/pq"
)

var DB *sql.DB

// Init opens the connection pool and pings.
func Init() error {
  url := os.Getenv("USER_DATABASE_URL")
  if url == "" {
    return fmt.Errorf("USER_DATABASE_URL not set")
  }
  var err error
  DB, err = sql.Open("postgres", url)
  if err != nil {
    return fmt.Errorf("sql.Open: %w", err)
  }
  if err = DB.Ping(); err != nil {
    return fmt.Errorf("DB.Ping: %w", err)
  }
  return nil
}
