package handlers

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/steven3002/warlot/warlot-publisher/internal/storage"
)

func GetUser(c *gin.Context) {
	address := c.GetHeader("X-Wallet-Address")
	if address == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "X-Wallet-Address header is required"})
		return
	}

	user, err := storage.GetUser(address)
	if err != nil {
		log.Println("failed to read user:", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch user"})
		return
	}
	if user == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"name":  user.Name,
		"email": user.Email,
	})
}
