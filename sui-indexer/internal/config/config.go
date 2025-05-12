package config

import (
    "os"
    "time"
)

type Config struct {
    DatabaseURL   string
    SuiRPCURL     string
    StartCursor   string
    RetryInterval time.Duration
}





func Load() *Config {
    retry := time.Second * 5

    dbURL := os.Getenv("DATABASE_URL")
    if dbURL == "" {
        dbURL = "postgres://localhost:5432/indexer"
    }

    rpcURL := os.Getenv("SUI_RPC_URL")
    if rpcURL == "" {
        rpcURL = "https://fullnode.testnet.sui.io:443"
    }

    startCursor := os.Getenv("START_CURSOR")
    if startCursor == "" {
        startCursor = "0"
    }

    return &Config{
        DatabaseURL:   dbURL,
        SuiRPCURL:     rpcURL,
        StartCursor:   startCursor,
        RetryInterval: retry,
    }
}