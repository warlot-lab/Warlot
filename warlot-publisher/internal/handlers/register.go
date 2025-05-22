package handlers

import (
    "log"
    "net/http"

    "github.com/gin-gonic/gin"
    "github.com/steven3002/warlot-publisher/internal/storage"
)

type RegisterRequest struct {
    Name  string `json:"name",binding:"required"`
    Email string `json:"email",binding:"required,email"`
}

func Register(c *gin.Context) {
    address := c.GetHeader("X-Wallet-Address")
    if address == "" {
        c.JSON(http.StatusBadRequest, gin.H{"error": "X-Wallet-Address header is required"})
        return
    }

    existingUser, err := storage.GetUser(address)
    if err != nil {
        log.Println("failed to read user:", err)
        c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check user"})
        return
    } else if existingUser != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "user already registered"})
        return
    }

    var req RegisterRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    user := storage.User{
        Name:  req.Name,
        Email: req.Email,
    }

    if err := storage.SaveUser(address, user); err != nil {
        log.Println("failed to save user:", err)
        c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save user"})
        return
    }

    c.JSON(http.StatusOK, gin.H{"message": "User registered successfully"})
}
