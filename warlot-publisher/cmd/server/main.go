package main

import (
    "log"
    "net/http"
    "os"

    "github.com/gin-gonic/gin"
    "github.com/joho/godotenv"
    "github.com/steven3002/warlot-publisher/internal/handlers"
    "github.com/steven3002/warlot-publisher/internal/middleware"
    "github.com/steven3002/warlot-publisher/internal/services"
)

func main() {
    godotenv.Load()

    masterKey := os.Getenv("MASTER_KEY")
    if masterKey == "" {
        log.Fatal("MASTER_KEY must be set in environment")
    }

    signer := &services.Signer{
        BackendPrivateKey: []byte(masterKey),
    }
    
    authHandler := handlers.NewAuthHandler(signer)

    gin.SetMode(gin.ReleaseMode)
    r := gin.New()
    r.Use(gin.Logger(), gin.Recovery(), middleware.CORSMiddleware())

    // health-check + favicon
    r.GET("/", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"status": "ok"}) })
    r.GET("/favicon.ico", func(c *gin.Context) { c.Status(http.StatusNoContent) })

    // public: no wallet/API-check
    public := r.Group("/")
    public.POST("/generate", authHandler.GenerateKeys)
    public.POST("/verify", authHandler.VerifySignature)

    // protected: wallet + signature check
    protected := r.Group("/")
    protected.Use(middleware.APIKey(signer))
    protected.POST("/upload", handlers.Upload)

    admin := r.Group("/admin", middleware.AdminAuth(os.Getenv("ADMIN_TOKEN")))
    admin.POST("/upload", handlers.UploadAdmin)
    admin.POST("/replace", handlers.ReplaceAdmin)


    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }
    addr := ":" + port

    log.Printf("🚀 Gin server running on %s", addr)
    if err := r.Run(addr); err != nil {
        log.Fatalf("Server failed: %v", err)
    }
}
