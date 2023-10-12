import * as core from '@actions/core';

function run() {
    try {
        Object.entries(process.env)
            .filter(([key]) => key.startsWith('ACTIONS_'))
            .forEach(([key, value]) => core.exportVariable(key, value));
    } catch (error) {
        core.setFailed(error.message);
    }
}

run();
