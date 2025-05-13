package blockchain

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"log"

	"github.com/joho/godotenv"
	"github.com/block-vision/sui-go-sdk/models"
	"github.com/block-vision/sui-go-sdk/signer"
	"github.com/block-vision/sui-go-sdk/sui"
	"github.com/steven3002/warlot-publisher/internal/wmodels"
	"github.com/steven3002/warlot-publisher/internal/constants"
	
)

// StoreBlobTx wraps the Move call and execution for the 'store_blob' function.
func StoreBlobTx(usersAddress string, resp *wmodels.UploadResponse, epochs, cycle uint64) error {
	// Convert numeric values to strings
	epochStr := strconv.FormatUint(epochs, 10)
	cycleStr := strconv.FormatUint(cycle, 10)


	godotenv.Load()

	packageID := os.Getenv("USER_CONTRACT_ID")
	moduleName := os.Getenv("MOVE_MODULE_NAME")
	adminCap := os.Getenv("ADMIN_CAP")
	sysCfgID := os.Getenv("SYSTEM_CFG_ID")
	mnemonic := os.Getenv("USER_MNEMONIC")
	
	
	cli := sui.NewSuiClient(constants.Testnet)
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



	// Prepare arguments
	
	args := []interface{}{adminCap, sysCfgID, resp.SuiObjectID, epochStr, cycleStr, usersAddress}

	// Build MoveCall request
	movReq := models.MoveCallRequest{
		Signer:          signerAcct.Address,
		PackageObjectId: packageID,
		Module:          moduleName,
		Function:        "store_blob",
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
	txRes, err := client.SignAndExecuteTransactionBlock(ctx, models.SignAndExecuteTransactionBlockRequest{
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

	// Attach results to response
	resp.TxDigest = txRes.Effects.TransactionDigest
	resp.MoveEffects = &txRes.Effects
	return nil
}


func ReplaceBlobTx(toAddress string, oldID string, resp *wmodels.UploadResponse, epochs, cycle uint64) error {
	// Convert numeric values to strings
	epochStr := strconv.FormatUint(epochs, 10)
	cycleStr := strconv.FormatUint(cycle, 10)


	godotenv.Load()

	packageID := os.Getenv("USER_CONTRACT_ID")
	moduleName := os.Getenv("MOVE_MODULE_NAME")
	adminCap := os.Getenv("ADMIN_CAP")
	sysCfgID := os.Getenv("SYSTEM_CFG_ID")
	mnemonic := os.Getenv("USER_MNEMONIC")
	
	
	cli := sui.NewSuiClient(constants.Testnet)
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



	// Prepare arguments
	
	args := []interface{}{adminCap, sysCfgID, oldID, resp.SuiObjectID, epochStr, cycleStr, toAddress}

	// Build MoveCall request
	movReq := models.MoveCallRequest{
		Signer:          signerAcct.Address,
		PackageObjectId: packageID,
		Module:          moduleName,
		Function:        "replace",
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
	txRes, err := client.SignAndExecuteTransactionBlock(ctx, models.SignAndExecuteTransactionBlockRequest{
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

	// Attach results to response
	resp.TxDigest = txRes.Effects.TransactionDigest
	resp.MoveEffects = &txRes.Effects
	return nil
}
