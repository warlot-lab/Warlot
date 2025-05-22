package storage

import (
    "database/sql"
    "fmt"
    "os"

    _ "github.com/lib/pq"
)

type User struct {
    Name  string
    Email string
}

var db *sql.DB

// Init opens the pool. Call once at startup.
func Init() error {
    url := os.Getenv("USER_DATABASE_URL")
    if url == "" {
        return fmt.Errorf("USER_DATABASE_URL is not set")
    }
    var err error
    db, err = sql.Open("postgres", url)
    if err != nil {
        return fmt.Errorf("opening database: %w", err)
    }
    if err = db.Ping(); err != nil {
        return fmt.Errorf("pinging database: %w", err)
    }
    return nil
}

// Close the pool. Call in defer.
func Close() error {
    if db != nil {
        return db.Close()
    }
    return nil
}

// SaveUser upserts a user by wallet_address.
func SaveUser(address string, user User) error {
    const q = `
        INSERT INTO public.users (wallet_address, name, email)
        VALUES ($1, $2, $3)
        ON CONFLICT (wallet_address)
        DO UPDATE SET
          name  = EXCLUDED.name,
          email = EXCLUDED.email;
    `
    _, err := db.Exec(q, address, user.Name, user.Email)
    return err
}

// GetUser fetches by wallet_address, returns (nil, nil) if not found.
func GetUser(address string) (*User, error) {
    const q = `
        SELECT name, email
          FROM public.users
         WHERE wallet_address = $1
    `
    var u User
    err := db.QueryRow(q, address).Scan(&u.Name, &u.Email)
    if err == sql.ErrNoRows {
        return nil, nil
    }
    if err != nil {
        return nil, err
    }
    return &u, nil
}
