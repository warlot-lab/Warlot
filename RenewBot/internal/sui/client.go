package sui

import (
	"context"
	"log"
	"os"

	"encoding/json"
	"strconv"

	"github.com/block-vision/sui-go-sdk/models"
	"github.com/block-vision/sui-go-sdk/sui"
	"github.com/joho/godotenv"
)

func GetWalrusEpoch() (uint64, uint64, error) {
	// Load environment
	godotenv.Load()

	walrusSystem := os.Getenv("WALRUS_SYSTEM")
	rpcURL := os.Getenv("RPC_URL")

	if walrusSystem == "" || rpcURL == "" {
		log.Fatal("Please set WALRUS_SYSTEM or RPC_URL environment vars")
	}

	cli := sui.NewSuiClient(rpcURL)
	client, ok := cli.(*sui.Client)
	if !ok {
		log.Fatal("Failed to create Sui client")
	}
	ctx := context.Background()

	rsp, err := client.SuiXGetDynamicFieldObject(ctx, models.SuiXGetDynamicFieldObjectRequest{
		ObjectId: walrusSystem,
		DynamicFieldName: models.DynamicFieldObjectName{
			Type:  "u64",
			Value: "1",
		},
	})

	if err != nil {
		log.Println("failed to fetch dynamic field: ", err)
	}

	fieldsMap := rsp.Data.Content.Fields

	// grab the "value" entry
	idIfc, ok := fieldsMap["value"]
	if !ok {
		log.Fatalf(`Fields map has no key "id"`)
	}
	idMap, ok := idIfc.(map[string]interface{})
	if !ok {
		log.Fatalf("unexpected type for Fields[\"id\"]: %T", idIfc)
	}

	// now get the actual field string out
	idStrIfc, ok := idMap["fields"]
	if !ok {
		log.Fatalf(`idMap has no key "id" %s`, idMap)
	}

	idStr, ok := idStrIfc.(map[string]interface{})
	if !ok {
		log.Fatalf("unexpected type for idMap[\"id\"]: %T", idStrIfc)
	}

	storageCost := extractStorageCost(idStr)

	committeeObj, ok := idStr["committee"]
	if !ok {
		log.Fatalf(`idMap has no key "id" %s`, idStr)
	}

	committeeMap, ok := committeeObj.(map[string]interface{})
	if !ok {
		log.Fatalf("unexpected type for idMap[\"id\"]: %T", idStrIfc)
	}

	committeeFieldsObj, ok := committeeMap["fields"]
	if !ok {
		log.Fatalf(`idMap has no key "id" %s`, idStr)
	}

	committeeFieldsMap, ok := committeeFieldsObj.(map[string]interface{})
	if !ok {
		log.Fatalf("unexpected type for idMap[\"id\"]: %T", idStrIfc)
	}

	epochIfc, ok := committeeFieldsMap["epoch"]
	if !ok {
		log.Fatalf(`committeeFieldsMap has no key "epoch"`)
	}

	// assert to float64
	epochF, ok := epochIfc.(float64)
	if !ok {
		log.Fatalf("epoch is not a number, got %T", epochIfc)
	}

	// cast to uint64
	epochU64 := uint64(epochF)

	log.Printf("at: %s epoch", &epochU64)

	return epochU64, storageCost, nil
}

func extractStorageCost(idStr map[string]interface{}) uint64 {
	raw, ok := idStr["storage_price_per_unit_size"]
	if !ok {
		log.Fatalf(`missing key "storage_price_per_unit_size"`)
	}

	var cost uint64
	switch v := raw.(type) {
	case float64:
		// JSON numbers default to float64
		cost = uint64(v)

	case string:
		// parse string digits
		parsed, err := strconv.ParseUint(v, 10, 64)
		if err != nil {
			log.Fatalf("cannot parse storage_price_per_unit_size string %q: %v", v, err)
		}
		cost = parsed

	case json.Number:
		// if you’ve decoded with UseNumber()
		parsed, err := v.Int64()
		if err != nil {
			log.Fatalf("cannot parse storage_price_per_unit_size json.Number %q: %v", v, err)
		}
		cost = uint64(parsed)

	default:
		log.Fatalf("unexpected type for storage_price_per_unit_size: %T (value: %+v)", raw, raw)
	}

	return cost
}
