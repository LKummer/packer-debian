package test

import (
	"os"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/gruntwork-io/terratest/modules/packer"
	"github.com/gruntwork-io/terratest/modules/ssh"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestPackerDebianBuild(t *testing.T) {
	templateName, ok := os.LookupEnv("TEST_EXISTING_TEMPLATE")
	if !ok {
		templateName := "packer-debian-test-" + uuid.NewString()
		packerOptions := &packer.Options{
			Template:   "debian.pkr.hcl",
			WorkingDir: "..",
			Vars: map[string]string{
				"template_name": templateName,
				"proxmox_node":  "bfte",
			},
		}
		preseedURL, ok := os.LookupEnv("PRESEED_URL")
		if ok {
			packerOptions.Vars = map[string]string{
				"template_name": templateName,
				"proxmox_node":  "bfte",
				"preseed_url":   preseedURL,
			}
		}

		defer deleteProxmoxVM(t, templateName)
		packer.BuildArtifact(t, packerOptions)
		// Proxmox takes a second to rename the template.
		time.Sleep(5 * time.Second)
	}

	sshKeyPair := generateED25519KeyPair(t)

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "terraform",
		Vars: map[string]interface{}{
			"cloud_init_public_keys": sshKeyPair.PublicKey,
			"proxmox_template":       templateName,
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	sshIP := terraform.Output(t, terraformOptions, "ssh_ip")
	sshUser := terraform.Output(t, terraformOptions, "user")
	password := terraform.Output(t, terraformOptions, "password")

	// Wait after cloning VM.
	time.Sleep(30 * time.Second)

	host := ssh.Host{
		Hostname:    sshIP,
		SshUserName: sshUser,
		SshKeyPair:  sshKeyPair,
		CustomPort:  22,
	}

	// Check Cloud Init ran successfully and SSH works.
	ssh.CheckSshCommand(t, host, "sudo cloud-init status --wait")

	// Check disk is resized after cloning.
	dhOutput := ssh.CheckSshCommand(t, host, "sudo df -h")
	assert.Regexp(t, "/dev/sda6 *14G", dhOutput)

	// Check SSH password authentication is disabled.
	err := ssh.CheckSshConnectionE(t, ssh.Host{
		Hostname:    sshIP,
		SshUserName: sshUser,
		Password:    password,
		CustomPort:  22,
	})
	assert.Error(t, err)

	// Check root password is locked.
	rootPasswordStatus := ssh.CheckSshCommand(t, host, "sudo passwd --status root")
	assert.Regexp(t, "^root L ", rootPasswordStatus)

	// Check Python is installed.
	ssh.CheckSshCommand(t, host, "python3 --version")
	ssh.CheckSshCommand(t, host, "pip --version")

	// Check sudo is installed.
	ssh.CheckSshCommand(t, host, "sudo --version")
}
