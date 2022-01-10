<?php

header("Content-Type: text/plain; charset=UTF-8");

if (false === opcache_reset())
{
    echo "DISABLED";
}
else
{
    echo "OK";
}

