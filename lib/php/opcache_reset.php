<?php

if (false === opcache_reset())
{
    echo "DISABLED";
}
else
{
    echo "OK";
}

