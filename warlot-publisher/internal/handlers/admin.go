package handlers

import (
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/steven3002/warlot/warlot-publisher/internal/blockchain"
	"github.com/steven3002/warlot/warlot-publisher/internal/constants"
	"github.com/steven3002/warlot/warlot-publisher/internal/utils"
	"github.com/steven3002/warlot/warlot-publisher/internal/walrus"
	"github.com/steven3002/warlot/warlot-publisher/internal/wmodels"
)

func UploadAdmin(c *gin.Context) {
	// file + tmp save
	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	filename := uuid.New().String() + "_" + file.Filename
	tmp := filepath.Join(os.TempDir(), filename)
	if err := c.SaveUploadedFile(file, tmp); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer os.Remove(tmp)

	// build response stub
	resp := &wmodels.UploadResponse{
		FileName:  file.Filename,
		Timestamp: time.Now().Format(time.RFC3339),
		Deletable: false,
	}

	//  parse epochs/cycle
	epochStr := c.DefaultPostForm("epochs", strconv.Itoa(constants.DefaultEpoch))
	epochs, _ := strconv.ParseUint(epochStr, 10, 64)
	if epochs == 0 {
		epochs = constants.DefaultEpoch
	}
	cycleStr := c.DefaultPostForm("cycle", "0")
	cycle, _ := strconv.ParseUint(cycleStr, 10, 64)

	// parse the deletable flag
	deletableStr := c.DefaultPostForm("deletable", "false")
	deletable, err := strconv.ParseBool(deletableStr)
	if err != nil {
		// invalid flag → default to false
		deletable = false
	}
	resp.Deletable = deletable

	//  WALRUS store
	rawOutput, err := walrus.Store(tmp, int(epochs), "testnet", deletable)
	clean := utils.RemoveANSI(rawOutput)
	resp.Output = utils.ParseSuccessInfo(clean)
	if err != nil {
		resp.Error = err.Error()
	}
	utils.ParseMetadata(clean, resp)

	//  on‐chain mint to “to” address
	toAddr := c.GetHeader("X-To-Address")
	if toAddr == "" {
		resp.Error += "; missing X-To-Address header"
	} else if resp.SuiObjectID != "" {
		err = blockchain.StoreBlobTx(toAddr, resp, epochs, cycle)
		if err != nil {
			resp.Error += "; tx failed: " + err.Error()
		}
	}

	c.JSON(http.StatusOK, resp)
}

func ReplaceAdmin(c *gin.Context) {
	// file + tmp (same as above)
	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	filename := uuid.New().String() + "_" + file.Filename
	tmp := filepath.Join(os.TempDir(), filename)
	if err := c.SaveUploadedFile(file, tmp); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer os.Remove(tmp)

	//  read headers
	toAddr := c.GetHeader("X-To-Address")
	oldID := c.GetHeader("X-Old-Object-ID")

	resp := &wmodels.UploadResponse{
		FileName:  file.Filename,
		Timestamp: time.Now().Format(time.RFC3339),
		Deletable: false,
	}

	// parse the deletable flag
	deletableStr := c.DefaultPostForm("deletable", "false")
	deletable, err := strconv.ParseBool(deletableStr)
	if err != nil {
		// invalid flag → default to false
		deletable = false
	}
	resp.Deletable = deletable

	//  parse epochs/cycle
	epochStr := c.DefaultPostForm("epochs", strconv.Itoa(constants.DefaultEpoch))
	epochs, _ := strconv.ParseUint(epochStr, 10, 64)
	if epochs == 0 {
		epochs = constants.DefaultEpoch
	}
	cycleStr := c.DefaultPostForm("cycle", "0")
	cycle, _ := strconv.ParseUint(cycleStr, 10, 64)

	//  WALRUS store (mint new blob)
	rawOutput, err := walrus.Store(tmp, int(epochs), "testnet", deletable)
	clean := utils.RemoveANSI(rawOutput)
	resp.Output = utils.ParseSuccessInfo(clean)
	if err != nil {
		resp.Error = err.Error()
	}
	utils.ParseMetadata(clean, resp)

	// on‐chain replace: remove oldID, register resp.SuiObjectID
	if toAddr == "" {
		resp.Error += "; missing X-To-Address header"
	} else if oldID == "" {
		resp.Error += "; missing X-Old-Object-ID header"
	} else if resp.SuiObjectID != "" {
		err = blockchain.ReplaceBlobTx(toAddr, oldID, resp, epochs, cycle)
		if err != nil {
			resp.Error += "; replace tx failed: " + err.Error()
		}
	}

	c.JSON(http.StatusOK, resp)
}
