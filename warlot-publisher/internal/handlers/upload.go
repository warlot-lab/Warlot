package handlers

import (
    "net/http"
    "os"
    "path/filepath"
    "time"
	"strconv"

    "github.com/gin-gonic/gin"
    "github.com/google/uuid"

    "github.com/steven3002/warlot-publisher/internal/wmodels"
    "github.com/steven3002/warlot-publisher/internal/utils"
    "github.com/steven3002/warlot-publisher/internal/walrus"
	"github.com/steven3002/warlot-publisher/internal/constants"
    "github.com/steven3002/warlot-publisher/internal/blockchain"
)






func Upload(c *gin.Context) {
    file, err := c.FormFile("file")
    if err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

	// save to temp
	filename := uuid.New().String() + "_" + file.Filename
    tmp := filepath.Join(os.TempDir(), filename)
    if err := c.SaveUploadedFile(file, tmp); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    defer os.Remove(tmp)

    resp := &wmodels.UploadResponse{
        FileName: file.Filename,
        Timestamp: time.Now().Format(time.RFC3339),
        Deletable: false,
    }


    deletableStr := c.DefaultPostForm("deletable", "false")
    deletable, err := strconv.ParseBool(deletableStr)
    if err != nil {
        // invalid flag → default to false
        deletable = false
    }
    resp.Deletable = deletable



    epochStr := c.DefaultPostForm("epochs", strconv.Itoa(constants.DefaultEpoch))
	epochs, err := strconv.ParseUint(epochStr, 10, 64)
	if err != nil || epochs == 0 {
		epochs = constants.DefaultEpoch
	}
	cycleStr := c.DefaultPostForm("cycle", "0")
	cycle, err := strconv.ParseUint(cycleStr, 10, 64)
	if err != nil {
		cycle = 0
	}

    rawOutput, err := walrus.Store(tmp, int(epochs), "testnet", deletable)
    clean := utils.RemoveANSI(rawOutput)

    resp.Output = utils.ParseSuccessInfo(clean)
    if err != nil {
        resp.Error = err.Error()
    }
	utils.ParseMetadata(clean, resp)

    // If WALRUS created a new SUI object, invoke Move transaction
	if resp.SuiObjectID != "" {
	

		// Retrieve user address from header
		address := c.GetHeader("X-Wallet-Address")
		if address == "" {
			resp.Error = resp.Error + "; missing address header"
		} else {
			// Perform on-chain transaction
			err = blockchain.StoreBlobTx( address, resp, epochs, cycle)
			if err != nil {
				resp.Error = resp.Error + "; tx failed: " + err.Error()
			}
		}
	}


    c.JSON(http.StatusOK, resp)
}
