import { parseArgs } from 'node:util';

import core from '@actions/core';
import cache from '@actions/cache';

const ACTIONS = {
    async restore(key, paths) {
        const cacheKey = await cache.restoreCache(paths, key);
        if (cacheKey !== key) {
            fail(`cache not found for key: ${key}`);
        }
    },
    async save(key, paths) {
        const cacheId = await cache.saveCache(paths, key);
        core.info(`cache saved with id: ${cacheId}`);
    }
};

function fail(msg) {
    core.warning(msg);
    process.exit(1);
}

async function main() {
    try {
        const { values: { key }, positionals: [action, ...paths] } = parseArgs({
            options: {
                key: {
                    type: 'string',
                    short: 'k'
                }
            },
            allowPositionals: true
        });
        if (!key) {
            return fail('key not specified');
        }
        if (!action || !(action in ACTIONS)) {
            return fail(`action not specified, valid actions: ${Object.keys(ACTIONS).join(', ')}`);
        }
        await ACTIONS[action](key, paths);
    } catch (error) {
        fail(error.message);
    }
}

main();
