package sui

import (
	"context"
	"fmt"
	"log"
	"os"
	"strconv"

	"github.com/block-vision/sui-go-sdk/models"
	"github.com/block-vision/sui-go-sdk/signer"

	"github.com/block-vision/sui-go-sdk/sui"
	"github.com/joho/godotenv"
)

// RenewBlob chain epoch renew
func RenewBlob(usersAddress []string, epochs uint64) error {
	// Convert numeric values to strings
	epochStr := strconv.FormatUint(epochs, 10)

	godotenv.Load()

	packageID := os.Getenv("WARLOT_PACKAGE_ID")
	moduleName := os.Getenv("MOVE_MODULE_NAME")
	adminCap := os.Getenv("ADMIN_CAP")
	sysCfgID := os.Getenv("SYSTEM_CFG_ID")
	walrusSysCfg := os.Getenv("WALRUS_SYSTEM")
	mnemonic := os.Getenv("USER_MNEMONIC")

	cli := sui.NewSuiClient("https://fullnode.testnet.sui.io")
	client, ok := cli.(*sui.Client)
	if !ok {
		log.Fatal("Failed to cast to *sui.Client")
	}

	signerAcct, err := signer.NewSignertWithMnemonic(mnemonic)

	if err != nil {
		fmt.Println("Signer creation failed: ", err)
		return fmt.Errorf("Signer creation failed: %v", err)
	}

	fmt.Println("Using address:", signerAcct.Address)

	ctx := context.Background()

	address := make([]interface{}, len(usersAddress))
	for i, addr := range usersAddress {
		address[i] = addr
	}

	// Prepare arguments

	args := []interface{}{adminCap, sysCfgID, walrusSysCfg, address, epochStr}

	// Build MoveCall request
	movReq := models.MoveCallRequest{
		Signer:          signerAcct.Address,
		PackageObjectId: packageID,
		Module:          moduleName,
		Function:        "renew",
		TypeArguments:   []interface{}{},
		Arguments:       args,
		Gas:             &[]string{os.Getenv("GAS_COIN_ID")}[0],
		GasBudget:       "50000000",
	}

	rsp, err := client.MoveCall(ctx, movReq)
	if err != nil {
		fmt.Println("move call failed: ", err)
		return fmt.Errorf("move call failed: %w", err)
	}

	// Sign & execute
	txRes, err := client.SignAndExecuteTransactionBlock(ctx, models.SignAndExecuteTransactionBlockRequest{
		TxnMetaData: rsp,
		PriKey:      signerAcct.PriKey,
		Options: models.SuiTransactionBlockOptions{
			ShowEffects: true,
		},
		RequestType: "WaitForLocalExecution",
	})
	if err != nil {
		fmt.Println("execute tx failed: ", err)
		return fmt.Errorf("execute tx failed: %w", err)
	}

	fmt.Println("this is my output: ", txRes.Effects.TransactionDigest)
	fmt.Println("Effects: ", txRes.Effects)
	return nil
}

// RenewBlob chain epoch renew
func SyncBlob(usersAddress []string, epochSet, epochCheckpoint uint64) error {
	// Convert numeric values to strings
	epochStr := strconv.FormatUint(epochSet, 10)
	epochCheckpointStr := strconv.FormatUint(epochCheckpoint, 10)
	godotenv.Load()

	packageID := os.Getenv("WARLOT_PACKAGE_ID")
	moduleName := os.Getenv("MOVE_MODULE_NAME")
	adminCap := os.Getenv("ADMIN_CAP")
	sysCfgID := os.Getenv("SYSTEM_CFG_ID")
	walrusSysCfg := os.Getenv("WALRUS_SYSTEM")
	mnemonic := os.Getenv("USER_MNEMONIC")

	cli := sui.NewSuiClient("https://fullnode.testnet.sui.io")
	client, ok := cli.(*sui.Client)
	if !ok {
		log.Fatal("Failed to cast to *sui.Client")
	}

	signerAcct, err := signer.NewSignertWithMnemonic(mnemonic)

	if err != nil {
		return fmt.Errorf("Signer creation failed: %v", err)
	}

	fmt.Println("Using address:", signerAcct.Address)

	ctx := context.Background()

	address := make([]interface{}, len(usersAddress))
	for i, addr := range usersAddress {
		address[i] = addr
	}

	// Prepare arguments

	args := []interface{}{adminCap, sysCfgID, walrusSysCfg, address, epochStr, epochCheckpointStr}

	// Build MoveCall request
	movReq := models.MoveCallRequest{
		Signer:          signerAcct.Address,
		PackageObjectId: packageID,
		Module:          moduleName,
		Function:        "sync_blob",
		TypeArguments:   []interface{}{},
		Arguments:       args,
		Gas:             &[]string{os.Getenv("GAS_COIN_ID")}[0],
		GasBudget:       "50000000",
	}

	rsp, err := client.MoveCall(ctx, movReq)
	if err != nil {
		return fmt.Errorf("move call failed: %w", err)
	}

	// Sign & execute
	_, err = client.SignAndExecuteTransactionBlock(ctx, models.SignAndExecuteTransactionBlockRequest{
		TxnMetaData: rsp,
		PriKey:      signerAcct.PriKey,
		Options: models.SuiTransactionBlockOptions{
			ShowEffects: true,
		},
		RequestType: "WaitForLocalExecution",
	})
	if err != nil {
		return fmt.Errorf("execute tx failed: %w", err)
	}

	return nil
}
