package script

import (
	"strings"

	bosherr "github.com/cloudfoundry/bosh-agent/internal/github.com/cloudfoundry/bosh-utils/errors"
	boshlog "github.com/cloudfoundry/bosh-agent/internal/github.com/cloudfoundry/bosh-utils/logger"
)

// ParallelScript unfortunetly does not conform
// to the Script interface since it returns a set of results
type ParallelScript struct {
	name       string
	allScripts []Script

	logTag string
	logger boshlog.Logger
}

type scriptResult struct {
	Script Script
	Error  error
}

func NewParallelScript(name string, scripts []Script, logger boshlog.Logger) ParallelScript {
	return ParallelScript{
		name:       name,
		allScripts: scripts,

		logTag: "ParallelScript",
		logger: logger,
	}
}

func (s ParallelScript) Run() (map[string]string, error) {
	existingScripts := s.findExistingScripts(s.allScripts)

	s.logger.Info(s.logTag, "Will run %d %s scripts in parallel", len(existingScripts), s.name)

	resultsChan := make(chan scriptResult)

	for _, script := range existingScripts {
		script := script
		go func() { resultsChan <- scriptResult{script, script.Run()} }()
	}

	var failedScripts, passedScripts []string

	results := map[string]string{}

	for i := 0; i < len(existingScripts); i++ {
		select {
		case r := <-resultsChan:
			jobName := r.Script.Tag()

			if r.Error == nil {
				passedScripts = append(passedScripts, jobName)
				results[jobName] = "executed"
				s.logger.Info(s.logTag, "'%s' script has successfully executed", r.Script.Path())
			} else {
				failedScripts = append(failedScripts, jobName)
				results[jobName] = "failed"
				s.logger.Error(s.logTag, "'%s' script has failed with error: %s", r.Script.Path(), r.Error)
			}
		}
	}

	err := s.summarizeErrs(passedScripts, failedScripts)

	return results, err
}

func (s ParallelScript) findExistingScripts(all []Script) []Script {
	var existing []Script

	for _, script := range all {
		if script.Exists() {
			s.logger.Debug(s.logTag, "Found '%s' script in job '%s'", s.name, script.Tag())
			existing = append(existing, script)
		} else {
			s.logger.Debug(s.logTag, "Did not find '%s' script in job '%s'", s.name, script.Tag())
		}
	}

	return existing
}

func (s ParallelScript) summarizeErrs(passedScripts, failedScripts []string) error {
	if len(failedScripts) > 0 {
		errMsg := "Failed Jobs: " + strings.Join(failedScripts, ", ")

		if len(passedScripts) > 0 {
			errMsg += ". Successful Jobs: " + strings.Join(passedScripts, ", ")
		}

		totalRan := len(passedScripts) + len(failedScripts)

		return bosherr.Errorf("%d of %d %s script(s) failed. %s.", len(failedScripts), totalRan, s.name, errMsg)
	}

	return nil
}
