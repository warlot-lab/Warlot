package blockchain

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/block-vision/sui-go-sdk/models"
	"github.com/block-vision/sui-go-sdk/sui"
	"github.com/joho/godotenv"
	"github.com/steven3002/warlot/warlot-publisher/internal/constants"
)

// Client wraps the Sui client and struct type config
type Client struct {
	svc        *sui.Client
	StructType string
}

// NewClient reads env vars and returns a configured Sui client
func NewClient() *Client {
	godotenv.Load()

	rpcURL := os.Getenv("SUI_RPC_URL")
	if rpcURL == "" {
		rpcURL = constants.Testnet
	}
	cli := sui.NewSuiClient(rpcURL)
	svc, ok := cli.(*sui.Client)
	if !ok {
		log.Fatal("failed to initialize Sui client")
	}
	st := os.Getenv("STRUCT_TYPE")
	if st == "" {
		log.Fatal("STRUCT_TYPE must be set in environment")
	}
	return &Client{svc: svc, StructType: st}
}

// GetAPIKey fetches the registry object for the given address and returns its "apikey" field
func (c *Client) GetAPIKey(ctx context.Context, address string) (string, error) {

	rsp, err := c.svc.SuiXGetOwnedObjects(ctx, models.SuiXGetOwnedObjectsRequest{
		Address: address,
		Query: models.SuiObjectResponseQuery{
			Filter:  models.ObjectFilterByStructType{StructType: c.StructType},
			Options: models.SuiObjectDataOptions{ShowContent: true},
		},
		Limit: 1,
	})
	if err != nil {
		return "", fmt.Errorf("fetch owned objects: %w", err)
	}
	if len(rsp.Data) == 0 {
		return "", fmt.Errorf("no registry object for address %s", address)
	}
	fields := rsp.Data[0].Data.Content.Fields
	val, ok := fields["warlot_sign_apikey"]
	if !ok {
		return "", fmt.Errorf("warlot_sign_apikey field missing on-chain")
	}
	return fmt.Sprintf("%v", val), nil
}
