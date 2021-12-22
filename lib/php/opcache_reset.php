<?php

if (false === opcache_reset())
{
    throw new RuntimeException("Unable to flush OPcache");
}

echo "OK";
